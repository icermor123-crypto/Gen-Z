# Gen Z Tienda: tienda compartida por gestores

Paquete inicial que conserva la identidad visual de Gen‑Z (turquesa, tipografía y tarjetas redondeadas) y adapta flujos tipo AWP de Cafetería: catálogo público, pedidos para recoger o domicilio, caja para ventas presenciales y panel de gestión. No copia los datos ni los módulos internos de SERGETRAN. Incluye estas vistas:

- `store.html` (y `index.html?store=...`): catálogo público con búsqueda/categorías, carrito y captura de pedidos de recogida o domicilio.
- `manager.html`: acceso de los gestores y precios propios para su enlace.
- `admin.html`: resumen, Caja con turnos, solicitudes y estados, compras recibidas, inventario y ajustes auditables, reportes, gestores, precios, costos y margen.
- `supabase/schema.sql`: tablas, políticas RLS y funciones transaccionales para recogida/domicilio, venta local, compra/reabastecimiento, cambios de stock, estados y protección de datos.

La app conserva el antiguo programa de inventario en `inventario-anterior.html` solo como referencia; **no está conectado a la tienda nueva**.

## Configuración necesaria

1. Haz una copia del repositorio actual antes de reemplazar archivos. El paquete conserva el inventario viejo en `inventario-anterior.html`; la tienda Gen‑Z nueva mantiene el estilo turquesa original, ahora con catálogo filtrable, pedidos de recogida/domicilio y Caja para ventas presenciales.
2. Crea un proyecto en Supabase. En **Project Settings → API** copia la Project URL y la clave pública (anon/publishable).
3. En el SQL Editor ejecuta el archivo completo `supabase/schema.sql`. Si ya habías aplicado una versión anterior, vuelve a ejecutar este SQL actualizado: agrega las columnas nuevas y reemplaza las funciones necesarias.
4. Edita `config.js` y pega la URL y la clave pública. No pongas `service_role`, contraseñas ni secretos en el repositorio. Esta clave pública está pensada para aparecer en el navegador; la protección real depende de RLS.
5. Sube todos los archivos de esta carpeta a la raíz del repositorio y publícalos en Vercel conectando el repositorio. Configura el dominio final en Supabase → Authentication → URL Configuration: Site URL y Redirect URLs HTTPS que cubran las rutas `admin.html` y `manager.html` del despliegue. No publiques la clave service_role.
6. Abre `admin.html`, crea la cuenta propietaria con el correo que administrará la tienda y confirma el correo si Supabase lo pide.
7. En el panel crea el nombre, identificador público, moneda y WhatsApp de la tienda. Luego añade productos con precio base, costo real, existencia e imagen. Si quieres que la URL raíz del sitio abra la tienda sin parámetros, copia su identificador en `defaultStoreSlug` dentro de `config.js`.
8. En **Gestores**, registra nombre, correo e identificador del gestor. Comparte con esa persona el enlace `manager.html` para que se registre con ese mismo correo y confirme la cuenta. Cuando esté verificada, pulsa **Vincular cuenta** en tu panel.
9. El gestor inicia sesión en `manager.html`, define sus precios, guarda y comparte únicamente su enlace personal `index.html?store=TU-TIENDA&ref=GESTOR`.
10. Prueba una venta desde Caja, un pedido para recoger y otro desde enlace de gestor; confirma que el inventario, canal, atribución y cifras cuadran. Activa domicilio solo después de configurar tarifa, zonas y ETA. Haz todas las pruebas antes de difundir la URL.

### Ejemplo de URL en GitHub Pages

`https://USUARIO.github.io/REPOSITORIO/index.html?store=mi-tienda&ref=ana`

El `ref` no es una contraseña: identifica la atribución de ventas. La seguridad real depende de las políticas RLS y de los permisos de Supabase incluidos en el SQL.

## Caja, compras e inventario

La **Caja** exige abrir turno con fondo inicial antes de registrar ventas presenciales; permite indicar efectivo recibido y ver el cambio, elegir transferencia/otro medio, anotar entradas/salidas justificadas y cerrar comparando efectivo contado con el esperado. Ventas en transferencia/otros medios no se suman a la gaveta. No se conecta a un terminal ni verifica transferencias externas.

El panel **Compras** registra mercadería recibida, costo por unidad, proveedor y gastos compartidos del lote. Los gastos se distribuyen según el valor de cada producto y el sistema actualiza el costo unitario promedio ponderado, las existencias y el historial de movimientos. **Inventario** permite ajustes con motivo obligatorio y conserva fecha, usuario, cantidad anterior y posterior. Las existencias no pueden hacerse negativas; las ventas/cancelaciones las registran automáticamente. La copia antigua permite importar productos, categorías, precios, costos y existencias, pero imágenes y operaciones históricas no se migran.

## Comparación de canales incorporada

- **Caja / presencial:** el negocio abre un turno, registra la venta y forma de pago; el stock se descuenta al guardar y queda asociada al turno.
- **Pedido online para recoger:** la app guarda una solicitud pendiente, conserva origen/gestor y prepara el enlace de WhatsApp; el cliente aún debe enviar el mensaje y el negocio confirmar.
- **Pedido online a domicilio:** disponible solo si el dueño lo activa y configura tarifa, zonas y ETA; registra dirección, modalidad y tarifa en el snapshot del pedido. No hay cálculo por zona ni validación automática de cobertura, por lo que el negocio debe verificar la dirección al aceptar.
- **Gestor:** el enlace personal conserva atribución y el panel muestra los pedidos y comisiones registrados.

## Cómo se calculan los importes

Para cada producto, el **precio base** es lo que corresponde al ingreso bruto de la tienda. El costo unitario es el costo real que registra el dueño. El dueño configura un mínimo por producto; el piso efectivo es el mayor entre el precio base, el costo unitario y el mínimo definido. El gestor puede elevar el precio para generar su parte, pero no rebajarlo por debajo del precio base. La base sigue siendo editable por el negocio y conviene revisar que cubra costos.

- **Total del cliente:** cantidad × precio que aparece en el enlace del gestor.
- **Parte del gestor:** cantidad × (precio fijado por el gestor − precio base). El sistema impide precio inferior al mínimo efectivo.
- **Ingreso base del negocio:** cantidad × precio base.
- **Costo:** cantidad × costo unitario guardado al crear el pedido.
- **Ganancia bruta del negocio:** ingreso base − costo. No incluye todavía gastos generales, impuestos, comisiones de pago o entrega.

Cada pedido conserva los importes y nombres como snapshots. Cambiar precios después no altera ventas anteriores. Una solicitud online pendiente no descuenta existencias; al confirmarla, la app comprueba y descuenta el stock de forma atómica. Si ya no hay suficiente stock, no permite confirmarla. Cancelar una solicitud pendiente no toca existencias; cancelar un pedido confirmado repone las unidades y registra el movimiento. Los estados avanzan por etapas y un pedido entregado no se puede reabrir. El gestor ve sus pedidos y comisión, pero no los teléfonos, direcciones ni costos unitarios del cliente. La comisión no se paga automáticamente: el negocio debe liquidarla por fuera.

## Alcance y límites honestos

- Los pedidos online quedan **pendientes** y el negocio coordina pago/entrega manualmente; no hay pasarela de pago, factura fiscal, cálculo por zonas, notificaciones automáticas, recuperación de contraseña personalizada ni liquidación bancaria a gestores. Cada intento conserva una clave para evitar duplicar el pedido al reintentar una misma solicitud.
- Los informes y paneles cargan hasta 500 pedidos recientes y 100 compras/movimientos recientes. No es aún una solución de gran volumen ni una auditoría contable formal.
- No hay conversión automática USD/CUP. Elige una sola moneda para la tienda y trabaja los costos en esa misma moneda para que la ganancia sea comparable. El esquema bloquea cambiar la moneda después de registrar el primer pedido o compra, para no deformar el historial.
- Las imágenes pueden subirse desde el panel (JPEG/PNG/WebP hasta 5 MB) a un bucket público de Supabase, o añadirse mediante URL HTTPS. Importar la copia antigua carga productos/precios/existencias; las fotos antiguas se vuelven a adjuntar en el panel. No uses fotos sin autorización.
- La app antigua de inventario no migra sus datos automáticamente. Conserva una copia y transfiere productos verificando costo, precio y existencias antes de abrir la tienda.
- Este paquete no ha sido desplegado en tu proyecto Supabase ni probado con tus cuentas reales. Sigue la lista de pruebas antes de usarlo comercialmente. Para una campaña pública, activa verificación antispam/rate limits en el borde o añade CAPTCHA; el formulario por sí solo no frena bots.

## Pruebas y publicación

Desde esta carpeta puedes correr la prueba de interfaz simulada con `node tests/browser-smoke.js` y `node tests/admin-smoke.js`. Comprueban el catálogo/carrito/domicilio con Supabase simulado y el render de paneles administrativos principales; **no prueban tus tablas, transacciones ni políticas RLS reales**. La sintaxis de JS/SQL y el JSON de configuración se validaron, pero el paquete no se ha ejecutado dentro de tu proyecto ni se ha desplegado a tu dominio. Sigue cada prueba de aceptación después de ejecutar el esquema en un proyecto Supabase de prueba.

## Accesibilidad y privacidad incluidas

Diseño adaptable a móvil, controles grandes, labels, foco visible de teclado, encabezados semánticos, nombres accesibles en controles de cantidad, anuncios de estados y preferencia de movimiento reducido. Aún se recomienda probar con lector de pantalla y navegación solo por teclado.

El catálogo público obtiene datos a través de una función RPC y no necesita acceso directo a tablas. El costo no se devuelve al público; los pedidos y contactos solo son legibles para la cuenta propietaria; los gestores solo pueden cambiar los precios asociados a su propio usuario. Nunca subas claves service-role. La clave anon/publishable es pública por diseño, pero RLS debe estar habilitado como en este esquema.

## Lista de pruebas antes de publicar

- Cuenta propietaria crea tienda y producto; una segunda cuenta propietaria no puede ver esos datos.
- Anónimo ve nombre, descripción, foto y precio público, pero no costo ni precio base.
- Gestor A no ve ni puede editar datos, precios u pedidos del gestor B.
- Precio del gestor menor que el precio base se rechaza incluso si se manipula la página.
- Pedido válido con enlace de gestor queda pendiente, guarda su origen/cifras y no descuenta stock hasta confirmarlo.
- Falta de stock, producto oculto y gestor desactivado impiden enviar el pedido.
- Dos envíos repetidos con la misma clave de solicitud no crean pedidos duplicados.
- Sin turno abierto no se registra venta en Caja. Con turno abierto, la venta presencial completada descuenta stock y registra la forma de pago.
- Una solicitud online pendiente no reduce existencias; al aceptarla se valida el stock, se descuenta y se registra el movimiento. Si se cancela luego, el stock se repone una sola vez.
- Un ajuste manual de inventario requiere motivo y se refleja en el historial.
- Cancelar un pedido pendiente no modifica stock; confirmar lo descuenta y cancelar después devuelve la existencia una sola vez.
- Confirmar un pedido y marcarlo entregado conserva atribución y margen.
- Abre un turno, registra ventas en efectivo y transferencia, añade un movimiento de caja y cierra con un conteo para comparar la diferencia.
- Comprueba que no se pueda registrar venta presencial sin un turno abierto.
- Registra una compra con dos productos y gasto compartido; comprueba costo promedio, stock e historial.
- Importa una copia antigua en una base de prueba, confirma duplicados omitidos y existencia inicial.
- Completa una compra desde teléfono, teclado y un lector de pantalla, y revisa el flujo de confirmación de pedidos.
