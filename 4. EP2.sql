CREATE TABLE VENTAS (
    id_venta NUMBER PRIMARY KEY,
    id_cliente NUMBER,
    id_producto NUMBER,
    cantidad NUMBER,
    precio_unitario NUMBER,
    total_venta NUMBER,
    fecha_venta DATE,
    descuento NUMBER DEFAULT 0
);

CREATE TABLE AUDITORIA_VENTAS (
    id_auditoria NUMBER PRIMARY KEY,
    id_venta NUMBER,
    accion VARCHAR2(50),
    fecha_registro DATE,
    usuario VARCHAR2(50)
);

CREATE SEQUENCE venta_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE auditoria_seq START WITH 1 INCREMENT BY 1;

-- 1. PACKAGE 

CREATE OR REPLACE PACKAGE pkg_ventas AS
    PROCEDURE realizar_venta(
        p_id_cliente IN NUMBER,
        p_id_producto IN NUMBER,
        p_cantidad IN NUMBER
    );
    
    FUNCTION calcular_descuento(p_id_cliente NUMBER) RETURN NUMBER;
    
END pkg_ventas;
/

CREATE OR REPLACE PACKAGE BODY pkg_ventas AS

    v_contador_ventas NUMBER := 0;

    PROCEDURE registrar_auditoria(p_id_venta NUMBER, p_accion VARCHAR2) IS
    BEGIN
        INSERT INTO auditoria_ventas 
        VALUES (auditoria_seq.NEXTVAL, p_id_venta, p_accion, SYSDATE, USER);
    END registrar_auditoria;

    FUNCTION calcular_descuento(p_id_cliente NUMBER) RETURN NUMBER IS
        v_categoria VARCHAR2(20);
        v_descuento NUMBER;
    BEGIN
        BEGIN
            SELECT categoria INTO v_categoria 
            FROM cliente 
            WHERE id_cliente = p_id_cliente;
            
            IF v_categoria = 'PREMIUM' THEN
                v_descuento := 15;
            ELSIF v_categoria = 'REGULAR' THEN
                v_descuento := 5;
            ELSE
                v_descuento := 0;
            END IF;
            
            RETURN v_descuento;
            
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN 0; 
            WHEN OTHERS THEN
                RETURN 0;
        END;
        
    END calcular_descuento;


    PROCEDURE realizar_venta(
        p_id_cliente IN NUMBER,
        p_id_producto IN NUMBER,
        p_cantidad IN NUMBER
    ) IS
        v_precio_producto NUMBER;
        v_descuento NUMBER;
        v_total NUMBER;
        v_id_venta NUMBER;
        v_stock_actual NUMBER;
    BEGIN
        -- 1. Verificar stock usando la función
        BEGIN
            SELECT cantidad INTO v_stock_actual
            FROM stock 
            WHERE id_producto = p_id_producto AND id_talla = 3; -- Talla M por defecto
            
            IF v_stock_actual < p_cantidad THEN
                RAISE_APPLICATION_ERROR(-20001, 'Stock insuficiente. Disponible: ' || v_stock_actual);
            END IF;
            
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20001, 'Producto no encontrado en stock');
        END;
        
        -- 2. Obtener precio del producto
        BEGIN
            SELECT precio INTO v_precio_producto
            FROM producto 
            WHERE id_producto = p_id_producto;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20002, 'Producto no encontrado');
        END;
        
        -- 3. Calcular descuento usando la función
        v_descuento := calcular_descuento(p_id_cliente);
        
        -- 4. Calcular total
        v_total := (v_precio_producto * p_cantidad) * (1 - v_descuento/100);
        
        -- 5. Generar ID de venta
        SELECT venta_seq.NEXTVAL INTO v_id_venta FROM DUAL;
        
        -- 6. Insertar venta
        INSERT INTO ventas VALUES (
            v_id_venta, p_id_cliente, p_id_producto, p_cantidad,
            v_precio_producto, v_total, SYSDATE, v_descuento
        );
        
        -- 7. Actualizar stock directamente
        UPDATE stock 
        SET cantidad = cantidad - p_cantidad
        WHERE id_producto = p_id_producto AND id_talla = 3;
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'No se pudo actualizar el stock');
        END IF;
        
        -- 8. Actualizar contador interno
        v_contador_ventas := v_contador_ventas + 1;
        
        -- 9. Registrar en auditoría (procedimiento privado)
        registrar_auditoria(v_id_venta, 'VENTA_REALIZADA');
        
        DBMS_OUTPUT.PUT_LINE('✅ Venta exitosa! ID: ' || v_id_venta || ', Total: $' || v_total || ', Descuento: ' || v_descuento || '%');
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE; -- Propagar el error
    END realizar_venta;

END pkg_ventas;
/

-- 2. FUNCIONES

CREATE OR REPLACE FUNCTION fn_verificar_stock(
    p_id_producto NUMBER, 
    p_cantidad NUMBER
) RETURN VARCHAR2 IS
    v_stock_actual NUMBER;
BEGIN
    SELECT NVL(SUM(cantidad), 0) INTO v_stock_actual
    FROM stock 
    WHERE id_producto = p_id_producto;
    
    IF v_stock_actual >= p_cantidad THEN
        RETURN 'DISPONIBLE';
    ELSE
        RETURN 'SIN_STOCK';
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'ERROR';
END fn_verificar_stock;
/

-- 3. PROCEDIMIENTO 

CREATE OR REPLACE PROCEDURE proc_actualizar_stock(
    p_id_producto NUMBER,
    p_cantidad NUMBER
) IS
    v_stock_actual NUMBER;
BEGIN
    -- Verificar stock disponible primero
    SELECT cantidad INTO v_stock_actual
    FROM stock 
    WHERE id_producto = p_id_producto AND id_talla = 3;
    
    IF v_stock_actual < p_cantidad THEN
        RAISE_APPLICATION_ERROR(-20003, 'Stock insuficiente. Disponible: ' || v_stock_actual);
    END IF;
    
    -- Actualizar stock
    UPDATE stock 
    SET cantidad = cantidad - p_cantidad
    WHERE id_producto = p_id_producto AND id_talla = 3; -- Talla M
    
    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'No se pudo actualizar el stock - producto no encontrado');
    END IF;
    
    DBMS_OUTPUT.PUT_LINE('Stock actualizado para producto: ' || p_id_producto);
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20003, 'Producto no encontrado en stock');
END proc_actualizar_stock;
/

-- 4. TRIGGER SIMPLE

CREATE OR REPLACE TRIGGER trg_after_venta
    AFTER INSERT ON ventas
    FOR EACH ROW
BEGIN
    -- Registrar en auditoría
    INSERT INTO auditoria_ventas 
    VALUES (auditoria_seq.NEXTVAL, :NEW.id_venta, 'TRIGGER_EJECUTADO', SYSDATE, USER);
    
    DBMS_OUTPUT.PUT_LINE('🔔 Trigger ejecutado para venta: ' || :NEW.id_venta);
    
END trg_after_venta;
/

-- EJEMPLOS DE USO

-- Ejemplo 1: Usar el package completo
BEGIN
    pkg_ventas.realizar_venta(
        p_id_cliente => 1,      -- Cliente Premium (15% descuento)
        p_id_producto => 1,     -- Zapatillas Nike
        p_cantidad => 2
    );
END;
/

-- Ejemplo 2: Usar la función independiente
DECLARE
    v_disponibilidad VARCHAR2(20);
BEGIN
    v_disponibilidad := fn_verificar_stock(1, 5);
    DBMS_OUTPUT.PUT_LINE('Disponibilidad producto 1: ' || v_disponibilidad);
    
    v_disponibilidad := fn_verificar_stock(2, 50);
    DBMS_OUTPUT.PUT_LINE('Disponibilidad producto 2: ' || v_disponibilidad);
END;
/

-- Ejemplo 3: Usar el procedimiento independiente
BEGIN
    proc_actualizar_stock(2, 1);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

-- Ejemplo 4: Insertar directamente
INSERT INTO ventas 
VALUES (venta_seq.NEXTVAL, 2, 3, 1, 64990, 64990, SYSDATE, 0);
COMMIT; 

-- Ver resultados
SELECT 'VENTAS: ' || COUNT(*) || ' registros' FROM ventas;
SELECT 'AUDITORIA: ' || COUNT(*) || ' registros' FROM auditoria_ventas;

-- Mostrar datos
SELECT * FROM ventas ORDER BY id_venta;
SELECT * FROM auditoria_ventas ORDER BY id_auditoria;
SELECT id_producto, cantidad FROM stock WHERE id_producto IN (1,2,3) ORDER BY id_producto;