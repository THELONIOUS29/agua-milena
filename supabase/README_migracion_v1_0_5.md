# Migracion 1.0.5

Para una base existente, ejecutar `parche_plan_v1_0_5.sql` en el SQL Editor
del proyecto Supabase usado por la aplicacion. Este parche conserva los datos.

Crea la tabla de precios, permite devoluciones en los items de venta,
actualiza el RPC de ventas y agrega el RPC que registra pagos y descuentos
en una transaccion. Los cobros requieren administrador o planta.

`base_datos_completa_agua_milena.sql` sirve para una instalacion nueva;
borra los esquemas de la aplicacion y no debe usarse como migracion.

## Verificacion Local

```powershell
npm.cmd install --prefix "$env:TEMP\agua-sql-check" @electric-sql/pglite
node scripts/verificar_plan_sql.mjs "$env:TEMP\agua-sql-check\node_modules\@electric-sql\pglite\dist\index.js"
flutter test --no-pub
```

La prueba SQL usa una base aislada y un contexto de sesion simulado. Verifica
precios por vendedor y distribuidora, devoluciones, stock, ruta abierta entre
dias, notas, pago con descuento, descuento completo y rechazo de cobros del
rol Vendedor. No altera el proyecto remoto ni sustituye la comprobacion de
los permisos y de los flujos en la aplicacion conectada a Supabase.

Despues de aplicar la migracion, actualizar la version de la app. Para web:

```powershell
flutter build web --release --no-wasm-dry-run
firebase.cmd deploy --only hosting
```
