
-- RECORD y VARRAY
DECLARE
    -- RECORD para definir un tipo de prenda 
    TYPE prenda_record IS RECORD (
        id_ropa NUMBER,
        nombre VARCHAR2(50),
        talla VARCHAR2(5),
        stock NUMBER
    );

    -- VARRAY para visualizar una lista de tallas disponibles
    TYPE tallas_array IS VARRAY(10) OF VARCHAR2(5);
    v_tallas tallas_array := tallas_array('XS', 'S', 'M', 'L', 'XL', 'XXL', '36', '38', '40', '42');

    v_prenda prenda_record;

BEGIN
    -- Usamos RECORD para guardar datos de ejemplo
    v_prenda.id_ropa := 1;
    v_prenda.nombre := 'Polera';
    v_prenda.talla := 'M';
    v_prenda.stock := 20;

    DBMS_OUTPUT.PUT_LINE('ID: ' || v_prenda.id_ropa);
    DBMS_OUTPUT.PUT_LINE('Nombre: ' || v_prenda.nombre);
    DBMS_OUTPUT.PUT_LINE('Talla: ' || v_prenda.talla);
    DBMS_OUTPUT.PUT_LINE('Stock: ' || v_prenda.stock);

    -- Recorremos el VARRAY
    FOR i IN 1..v_tallas.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE('Tallas disponibles: ' || v_tallas(i));
    END LOOP;
END;
/


-- Cursores explicitos complejos para consultar prendas con bajo stock
DECLARE
    v_id        PRODUCTO.ID_PRODUCTO%TYPE;
    v_nombre    PRODUCTO.NOMBRE%TYPE;
    v_talla     TALLA.DESCRIPCION%TYPE;
    v_cantidad  STOCK.CANTIDAD%TYPE;     
    
    CURSOR cur_prendas_bajo_stock(p_min NUMBER) IS
        SELECT p.ID_PRODUCTO, p.NOMBRE, t.DESCRIPCION, s.CANTIDAD
        FROM PRODUCTO p
        JOIN STOCK s ON p.ID_PRODUCTO = s.ID_PRODUCTO
        JOIN TALLA t ON s.ID_TALLA = t.ID_TALLA
        WHERE s.CANTIDAD < p_min;
BEGIN
    OPEN cur_prendas_bajo_stock(-8);
    LOOP
        FETCH cur_prendas_bajo_stock
        INTO v_id, v_nombre, v_talla, v_cantidad;
        EXIT WHEN cur_prendas_bajo_stock%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE('Prenda: ' || v_nombre);
        DBMS_OUTPUT.PUT_LINE('Talla: ' || v_talla);
        DBMS_OUTPUT.PUT_LINE('Stock: ' || v_cantidad);
    END LOOP;
    CLOSE cur_prendas_bajo_stock;
END;
/



--Cursor para análisis de stock total por categoría de ropa con loops anidados
DECLARE
    v_categoria     MODELO.NOMBRE%TYPE;
    v_producto      PRODUCTO.NOMBRE%TYPE;
    v_total_stock   NUMBER;

    CURSOR cur_categoria IS
        SELECT ID_MODELO, NOMBRE
        FROM MODELO;

    CURSOR cur_producto_categoria(p_id_modelo NUMBER) IS
        SELECT p.NOMBRE, s.CANTIDAD
        FROM PRODUCTO p
        JOIN STOCK s ON p.ID_PRODUCTO = s.ID_PRODUCTO
        WHERE p.ID_MODELO = p_id_modelo;
BEGIN
    FOR cat_rec IN cur_categoria LOOP
        DBMS_OUTPUT.PUT_LINE('Categoría: ' || cat_rec.NOMBRE);

        FOR prod_rec IN cur_producto_categoria(cat_rec.ID_MODELO) LOOP
            DBMS_OUTPUT.PUT_LINE('Prenda: ' || prod_rec.NOMBRE);
            DBMS_OUTPUT.PUT_LINE('Stock: ' || prod_rec.CANTIDAD);
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('----------------------------');
    END LOOP;
END;
/

--Excepciones Predefinidas en PL/SQL
DECLARE
    v_stock_actual NUMBER;
    v_prenda_id NUMBER := 15;
BEGIN
    SELECT CANTIDAD INTO v_stock_actual
    FROM STOCK
    WHERE ID_PRODUCTO = v_prenda_id;

    DBMS_OUTPUT.PUT_LINE('Stock actual de la prenda ' || v_prenda_id || ': ' || v_stock_actual);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: La prenda con ID ' || v_prenda_id || ' no existe');

    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE('Error: Múltiples registros para la misma prenda');

END;
/

-- Pruebas de excepciones personalizadas en PL/SQL
DECLARE
    stock_negativo EXCEPTION;
    talla_no_valida EXCEPTION;
    PRAGMA EXCEPTION_INIT(stock_negativo, -20001);
    PRAGMA EXCEPTION_INIT(talla_no_valida, -20002);

    v_nueva_cantidad NUMBER := -5;
    v_talla VARCHAR2(3) := 'XXX';
BEGIN
    -- Validacioón stock negativo
    IF v_nueva_cantidad < 0 THEN
        RAISE stock_negativo;
    END IF;

    -- Validación talla válida
    IF v_talla NOT IN ('XS', 'S', 'M', 'L', 'XL', 'XXL', '36', '38', '40', '42') THEN
        RAISE talla_no_valida;
    END IF;

EXCEPTION
    WHEN stock_negativo THEN
        DBMS_OUTPUT.PUT_LINE('Error: El stock no puede ser negativo');
    WHEN talla_no_valida THEN
        DBMS_OUTPUT.PUT_LINE('Error: Talla ' || v_talla || ' no es válida');    
END;
/

-- SQL para la gestión de inventario de ropa
CREATE OR REPLACE PACKAGE PKG_INVENTARIO_ROPA AS
    PROCEDURE actualizar_stock(p_id_producto NUMBER, p_cantidad NUMBER);
    PROCEDURE generar_reporte_stock;
    FUNCTION calcular_stock_total(p_id_modelo NUMBER) RETURN NUMBER;
    FUNCTION validar_talla(p_talla VARCHAR2) RETURN BOOLEAN;
END PKG_INVENTARIO_ROPA;
/

-- Tabla para trigger auditoria

CREATE OR REPLACE TRIGGER trg_auditoria_stock
  AFTER UPDATE OF cantidad ON STOCK 
  FOR EACH ROW 
BEGIN
  INSERT INTO AUDITORIA_STOCK (id_producto, stock_anterior, stock_nuevo, fecha_cambio) VALUES (
    :OLD.ID_PRODUCTO,  
    :OLD.CANTIDAD,    
    :NEW.CANTIDAD,    
    SYSDATE       
  );

  --Mensaje de confirmación
  DBMS_OUTPUT.PUT_LINE('Auditoría registrada para producto: ' || :OLD.ID_PRODUCTO);
END;
/


--Crear la tabla de auditoría que no existe
CREATE TABLE AUDITORIA_STOCK (
  id_auditoria   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_producto   NUMBER NOT NULL,
  stock_anterior  NUMBER NOT NULL,
  stock_nuevo   NUMBER NOT NULL,
  fecha_cambio   DATE DEFAULT SYSDATE,
  usuario     VARCHAR2(50) DEFAULT USER
);