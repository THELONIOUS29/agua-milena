# Saldo a favor en el pago del despacho

Primero ejecutar `parche_saldo_favor_despacho.sql` en el SQL Editor del
proyecto Supabase de Agua Milena. Requiere los parches actuales de sesiones,
ventas y saldo explícito. La migración es repetible y no modifica importes
existentes. Después compilar y distribuir la aplicación.

En el detalle del despacho, abrir **Registrar pago / Descuento** y marcar
**Aplicar saldo a favor al despacho**. La opción aparece si hay deuda y crédito
disponible en otros despachos del mismo vendedor. No consume crédito hasta
confirmar **Registrar pago**. También admite aplicar solamente crédito,
dejando vacío el monto cobrado. **Todo** calcula el efectivo restante después
del descuento y del crédito seleccionados.

Ejemplo: pendiente 103.35 y crédito disponible 14.83: se aplican 14.83 y quedan
88.52 por pagar. Si el crédito supera la deuda, el remanente sigue disponible.
El crédito reduce el total del despacho y no se registra como efectivo.

La función exige sesión admin/planta, bloquea al vendedor igual que el RPC de
ventas y valida nuevamente los importes antes de consumir el crédito. Si el
saldo cambió, rechaza la operación completa. Los reintentos con el mismo
identificador no generan otro descuento ni otro abono. La tabla interna
`rutas.aplicaciones_saldo` guarda monto, efectivo, descuento, usuario y despachos
de origen; no admite acceso directo desde el cliente. Las notas de los
despachos también dejan constancia de la transferencia.

Validación local:

```text
flutter test --no-pub test/saldo_favor_despacho_test.dart
node scripts/verificar_plan_sql.mjs <ruta-a-pglite/dist/index.js>
```

Las pruebas SQL incluyen migración repetible, crédito parcial/total, remanente,
reintento, rechazo por falta de saldo, permisos, importes inválidos y venta
posterior que solo consume el saldo restante. Se ejecutan en PostgreSQL local
con PGlite y no generan operaciones en producción.
