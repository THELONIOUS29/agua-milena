# Correccion de devoluciones, saldos y pagos

Ejecutar `parche_devoluciones_y_saldo_explicito.sql` en Supabase SQL Editor,
despues del parche de la version 1.0.5 y antes de actualizar la app a 4010.

La consulta final debe mostrar `permite_devoluciones = true` para Yovany y
`false` para Oliver y los demas vendedores. El nombre se compara sin distinguir
mayusculas y admite apellidos. Si Yovany tiene otro nombre registrado, ajustar
la seleccion antes de ejecutar el parche.

El permiso queda guardado en el registro del vendedor. La app carga productos
del inventario para devolverlos, aunque no existan ventas recientes ni stock
disponible para una nueva salida.

El saldo a favor deja de aplicarse automaticamente. Por ejemplo, 195 bidones
a 0.53 dan 103.35 a cobrar; un saldo previo de 14.83 solo se utiliza si el
operador marca expresamente Aplicar saldo a favor.

La validacion de sesiones fija su search_path para encontrar pgcrypto desde
el RPC de pagos. Esto corrige el error digest(bytea, unknown).

El parche conserva ventas, cobros y creditos ya registrados. No restaura
creditos historicos ni cambia importes de ventas anteriores. Esos datos deben
revisarse antes de cualquier correccion individual.

Las pruebas SQL usan PostgreSQL con pgcrypto y sesiones cifradas reales.
Reproducen el error de digest antes de corregirlo, prueban el caso 103.35/14.83,
verifican devoluciones de Yovany y rechazo de devoluciones para Oliver, y
mantienen las restricciones de pago para el rol Vendedor.
