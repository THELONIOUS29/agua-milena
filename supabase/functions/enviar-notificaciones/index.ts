import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type SolicitudNotificacion = {
  titulo?: string;
  cuerpo?: string;
  rol?: string | null;
  revision?: "operativa";
  solo_resumen?: boolean;
  usuario_id?: string | null;
  tokens?: string[];
  token_sesion?: string | null;
  datos?: Record<string, string | number | boolean | null>;
};

type TokenNotificacion = {
  token_firebase: string;
  usuario_id: string;
  rol: string;
};

type ProductoOperativo = {
  nombre: string;
  stock: number;
  stock_minimo: number;
  stock_bajo_calculado?: number | null;
};

type VentaOperativa = {
  fecha: string;
  total: number | string;
  items_json?: Array<{
    nombre_producto?: string;
    cantidad?: number;
  }>;
};

type PrediccionModeloGuardada = {
  clave: string;
  tipo: string;
  fecha_objetivo: string;
  titulo: string;
  cuerpo: string;
  demanda_bidones?: number | null;
  demanda_fundas?: number | null;
  carga_bidones?: number | null;
  carga_fundas?: number | null;
  riesgo_stock_bajo?: number | string | null;
  venta_alta_inesperada?: number | string | null;
  dia_pico?: string | null;
  temporada_nombre?: string | null;
  dias_restantes?: number | null;
  modelo_nombre?: string | null;
};

type AvisoOperativo = {
  titulo: string;
  cuerpo: string;
  datos: Record<string, string | number | boolean | null>;
};

type TemporadaOperativa = {
  nombre: string;
  mes: number;
  dia: number;
};

type FechaLocal = {
  anio: number;
  mes: number;
  dia: number;
  hora: number;
  diaSemana: number;
};

type UsuarioSesion = {
  id: string;
  rol: string;
  activo: boolean;
};

const encabezadosCors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-notificaciones-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (solicitud) => {
  if (solicitud.method === "OPTIONS") {
    return new Response("ok", { headers: encabezadosCors });
  }

  try {
    const cuerpoSolicitud = (await solicitud.json()) as SolicitudNotificacion;
    const sesionApp = await validarAutorizacion(solicitud, cuerpoSolicitud);
    if (cuerpoSolicitud.revision === "operativa") {
      validarPermisoRevisionOperativa(sesionApp);
      return await ejecutarRevisionOperativa(cuerpoSolicitud);
    }

    const titulo = cuerpoSolicitud.titulo ?? "Agua Milena";
    const cuerpo =
      cuerpoSolicitud.cuerpo ?? "Tienes una alerta importante pendiente.";
    const tokens = await resolverTokens(cuerpoSolicitud, sesionApp);

    if (tokens.length === 0) {
      return respuestaJson({ enviados: 0, errores: 0, detalle: [] });
    }

    const tokenAcceso = await obtenerTokenAccesoFirebase();
    const resultados = await Promise.all(
      tokens.map((token) =>
        enviarNotificacionFirebase({
          token,
          titulo,
          cuerpo,
          datos: cuerpoSolicitud.datos ?? {},
          tokenAcceso,
        }),
      ),
    );
    await desactivarTokensInvalidos(resultados);

    return respuestaJson({
      enviados: resultados.filter((resultado) => resultado.ok).length,
      errores: resultados.filter((resultado) => !resultado.ok).length,
      detalle: resultados,
    });
  } catch (error) {
    return respuestaJson(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

async function ejecutarRevisionOperativa(
  solicitud: SolicitudNotificacion,
): Promise<Response> {
  const avisos = await construirAvisosOperativos();
  if (solicitud.solo_resumen === true) {
    return respuestaJson({ avisos: avisos.length, detalle: avisos });
  }

  if (avisos.length === 0) {
    return respuestaJson({ enviados: 0, errores: 0, avisos: 0, detalle: [] });
  }

  const tokens = await resolverTokens({ rol: solicitud.rol ?? "admin" });
  if (tokens.length === 0) {
    return respuestaJson({ enviados: 0, errores: 0, avisos: avisos.length });
  }

  const tokenAcceso = await obtenerTokenAccesoFirebase();
  const resultados = [];
  for (const aviso of avisos) {
    const enviados = await Promise.all(
      tokens.map((token) =>
        enviarNotificacionFirebase({
          token,
          titulo: aviso.titulo,
          cuerpo: aviso.cuerpo,
          datos: aviso.datos,
          tokenAcceso,
        }),
      ),
    );
    resultados.push(...enviados);
  }
  await desactivarTokensInvalidos(resultados);

  return respuestaJson({
    enviados: resultados.filter((resultado) => resultado.ok).length,
    errores: resultados.filter((resultado) => !resultado.ok).length,
    avisos: avisos.length,
    detalle: resultados,
  });
}

async function construirAvisosOperativos() {
  const avisos: AvisoOperativo[] = [];

  const productos = await consultarProductosOperativos();

  const productosCriticos = productos.filter(
    (producto) => Number(producto.stock) <= Number(producto.stock_minimo),
  );
  for (const producto of productosCriticos) {
    avisos.push({
      titulo: "Stock urgente",
      cuerpo: `${producto.nombre}: quedan ${producto.stock} unidad. Esta en el minimo o por debajo del minimo configurado (${producto.stock_minimo}).`,
      datos: {
        tipo: "stock_urgente",
        clave: `stock_urgente:${normalizarClave(producto.nombre)}`,
        producto: producto.nombre,
      },
    });
  }

  const productosBajos = productos.filter(
    (producto) =>
      Number(producto.stock) > Number(producto.stock_minimo) &&
      Number(producto.stock) <= limiteStockBajo(producto),
  );
  for (const producto of productosBajos) {
    avisos.push({
      titulo: "Stock bajo",
      cuerpo: `${producto.nombre}: quedan ${producto.stock} unidad. El stock esta cerca del minimo (${producto.stock_minimo}).`,
      datos: {
        tipo: "stock_bajo",
        clave: `stock_bajo:${normalizarClave(producto.nombre)}`,
        producto: producto.nombre,
      },
    });
  }

  const rutas = await consultarRegistros<{
    id: string;
    fecha: string;
    monto_total: number | string;
    monto_cobrado: number | string;
    estado: string;
  }>(
    "rutas",
    "rutas",
    "select=id,fecha,monto_total,monto_cobrado,estado&estado=neq.pagado&order=fecha.desc&limit=100",
  );
  const rutasPendientes = rutas.filter(
    (ruta) => Number(ruta.monto_total) - Number(ruta.monto_cobrado) > 0.009,
  );
  for (const ruta of rutasPendientes) {
    const saldoPendiente =
      Number(ruta.monto_total) - Number(ruta.monto_cobrado);
    avisos.push({
      titulo: "Cobros pendientes",
      cuerpo: `El despacho del ${ruta.fecha} tiene saldo pendiente por cobrar: $${saldoPendiente.toFixed(2)}.`,
      datos: {
        tipo: "cobros_pendientes",
        clave: `cobros_pendientes:${ruta.id}`,
        ruta_id: ruta.id,
      },
    });
  }

  avisos.push(...(await construirAvisosModeloInteligenteSeguro()));

  return avisos;
}

async function construirAvisosModeloInteligenteSeguro(): Promise<
  AvisoOperativo[]
> {
  try {
    return await construirAvisosModeloInteligente();
  } catch (error) {
    console.error("No se pudieron construir avisos inteligentes", error);
    return [];
  }
}

async function consultarProductosOperativos(): Promise<ProductoOperativo[]> {
  try {
    return await consultarRegistros<ProductoOperativo>(
      "inventario",
      "productos",
      "select=nombre,stock,stock_minimo,stock_bajo_calculado",
    );
  } catch (error) {
    console.error(
      "No se pudo consultar stock_bajo_calculado, usando consulta compatible",
      error,
    );
    return await consultarRegistros<ProductoOperativo>(
      "inventario",
      "productos",
      "select=nombre,stock,stock_minimo",
    );
  }
}

async function construirAvisosModeloInteligente(): Promise<AvisoOperativo[]> {
  const fecha = fechaLocalEcuador();
  if (fecha.hora !== 7) return [];

  const predicciones = await consultarPrediccionesModeloGuardadas(fecha);
  const vistas = new Map<string, PrediccionModeloGuardada>();
  for (const prediccion of predicciones) {
    vistas.set(prediccion.clave, prediccion);
  }

  return [...vistas.values()].map(avisoDesdePrediccionGuardada);
}

async function consultarPrediccionesModeloGuardadas(
  fecha: FechaLocal,
): Promise<PrediccionModeloGuardada[]> {
  const hoy = new Date(Date.UTC(fecha.anio, fecha.mes - 1, fecha.dia));
  const hoySql = formatoFechaUtc(hoy);
  const consultas: Promise<PrediccionModeloGuardada[]>[] = [
    consultarPrediccionesPorFiltro(
      `tipo=eq.diaria&fecha_objetivo=eq.${hoySql}`,
    ),
  ];

  if (fecha.diaSemana === 1) {
    const finSemanaSql = formatoFechaUtc(
      new Date(hoy.getTime() + 6 * 86_400_000),
    );
    consultas.push(
      consultarPrediccionesPorFiltro(
        `tipo=eq.semanal&fecha_objetivo=eq.${hoySql}`,
      ),
      consultarPrediccionesPorFiltro(
        `tipo=eq.temporada_semana&fecha_objetivo=gte.${hoySql}&fecha_objetivo=lte.${finSemanaSql}`,
      ),
    );
  }

  if (fecha.dia === 1) {
    const finMesSql = formatoFechaUtc(
      new Date(Date.UTC(fecha.anio, fecha.mes, 0)),
    );
    consultas.push(
      consultarPrediccionesPorFiltro(
        `tipo=eq.mensual&fecha_objetivo=eq.${hoySql}`,
      ),
      consultarPrediccionesPorFiltro(
        `tipo=eq.temporada_mes&fecha_objetivo=gte.${hoySql}&fecha_objetivo=lte.${finMesSql}`,
      ),
    );
  }

  consultas.push(
    consultarPrediccionesPorFiltro(
      `tipo=eq.temporada_dia&fecha_objetivo=eq.${hoySql}`,
    ),
  );

  const resultados = await Promise.all(consultas);
  return resultados.flat();
}

async function consultarPrediccionesPorFiltro(
  filtro: string,
): Promise<PrediccionModeloGuardada[]> {
  return await consultarRegistros<PrediccionModeloGuardada>(
    "inventario",
    "predicciones_modelo_alertas",
    `select=clave,tipo,fecha_objetivo,titulo,cuerpo,demanda_bidones,demanda_fundas,carga_bidones,carga_fundas,riesgo_stock_bajo,venta_alta_inesperada,dia_pico,temporada_nombre,dias_restantes,modelo_nombre&${filtro}&origen=eq.tflite&order=actualizado_en.desc&limit=10`,
  );
}

function avisoDesdePrediccionGuardada(
  prediccion: PrediccionModeloGuardada,
): AvisoOperativo {
  return {
    titulo: prediccion.titulo,
    cuerpo: prediccion.cuerpo,
    datos: {
      tipo: prediccion.tipo,
      clave: prediccion.clave,
      fecha_objetivo: prediccion.fecha_objetivo,
      demanda_bidones: prediccion.demanda_bidones ?? null,
      demanda_fundas: prediccion.demanda_fundas ?? null,
      carga_bidones: prediccion.carga_bidones ?? null,
      carga_fundas: prediccion.carga_fundas ?? null,
      riesgo_stock_bajo: prediccion.riesgo_stock_bajo ?? null,
      venta_alta_inesperada: prediccion.venta_alta_inesperada ?? null,
      dia_pico: prediccion.dia_pico ?? null,
      temporada: prediccion.temporada_nombre ?? null,
      dias_restantes: prediccion.dias_restantes ?? null,
      modelo: prediccion.modelo_nombre ?? null,
    },
  };
}

function estimarPrediccionPeriodo({
  productos,
  ventas,
  fecha,
  dias,
}: {
  productos: ProductoOperativo[];
  ventas: VentaOperativa[];
  fecha: FechaLocal;
  dias: number;
}) {
  const stockBidones = productos
    .filter((producto) => esBidon(producto.nombre))
    .reduce((suma, producto) => suma + Number(producto.stock), 0);
  const stockFundas = productos
    .filter((producto) => esFunda(producto.nombre))
    .reduce((suma, producto) => suma + Number(producto.stock), 0);
  const promedio7 = promedioVentas(ventas, 7, fecha);
  const promedio30 = promedioVentas(ventas, 30, fecha);

  let demandaBidones = 0;
  let demandaFundas = 0;
  let riesgoStockBajo = 0;
  let diaPico = "";
  let demandaPico = -1;
  for (let indice = 0; indice < dias; indice++) {
    const actual = new Date(
      Date.UTC(fecha.anio, fecha.mes - 1, fecha.dia + indice),
    );
    const base = demandaBaseOperativa(diaSemanaDesdeFecha(actual));
    const bidones = proyectarDemanda({
      base: base.bidones,
      promedio7: promedio7.bidones,
      promedio30: promedio30.bidones,
      tieneHistorial: promedio7.tieneHistorial || promedio30.tieneHistorial,
    });
    const fundas = proyectarDemanda({
      base: base.fundas,
      promedio7: promedio7.fundas,
      promedio30: promedio30.fundas,
      tieneHistorial: promedio7.tieneHistorial || promedio30.tieneHistorial,
    });
    demandaBidones += bidones;
    demandaFundas += fundas;
    riesgoStockBajo = Math.max(
      riesgoStockBajo,
      Math.round(
        probabilidadStockBajo(stockBidones, stockFundas, bidones, fundas) * 100,
      ),
    );

    if (bidones + fundas > demandaPico) {
      demandaPico = bidones + fundas;
      diaPico = formatoFechaCorta(actual);
    }
  }

  return {
    demandaBidones,
    demandaFundas,
    cargaBidones: Math.ceil(demandaBidones * 1.15),
    cargaFundas: Math.ceil(demandaFundas * 1.15),
    riesgoStockBajo,
    diaPico,
  };
}

function promedioVentas(
  ventas: VentaOperativa[],
  dias: number,
  fecha: FechaLocal,
) {
  if (ventas.length === 0)
    return { bidones: 0, fundas: 0, tieneHistorial: false };
  const hoy = new Date(Date.UTC(fecha.anio, fecha.mes - 1, fecha.dia));
  const inicio = new Date(hoy.getTime() - dias * 86_400_000);
  const ventasPeriodo = ventas.filter((venta) => {
    const fechaVenta = new Date(`${venta.fecha}T00:00:00Z`);
    return fechaVenta >= inicio && fechaVenta < hoy;
  });
  if (ventasPeriodo.length === 0)
    return { bidones: 0, fundas: 0, tieneHistorial: false };

  const totales = ventasPeriodo.reduce(
    (suma, venta) => {
      const items = Array.isArray(venta.items_json) ? venta.items_json : [];
      for (const item of items) {
        const nombre = item.nombre_producto ?? "";
        const cantidad = Number(item.cantidad ?? 0);
        if (esBidon(nombre)) suma.bidones += cantidad;
        if (esFunda(nombre)) suma.fundas += cantidad;
      }
      return suma;
    },
    { bidones: 0, fundas: 0 },
  );
  return {
    bidones: totales.bidones / dias,
    fundas: totales.fundas / dias,
    tieneHistorial: totales.bidones > 0 || totales.fundas > 0,
  };
}

function proyectarDemanda({
  base,
  promedio7,
  promedio30,
  tieneHistorial,
}: {
  base: number;
  promedio7: number;
  promedio30: number;
  tieneHistorial: boolean;
}) {
  if (!tieneHistorial) return Math.ceil(base);

  const promedioReciente =
    promedio7 > 0 && promedio30 > 0
      ? promedio7 * 0.7 + promedio30 * 0.3
      : Math.max(promedio7, promedio30);
  const pisoOperativo = base * 0.55;
  return Math.ceil(Math.max(promedioReciente, promedio30 * 0.9, pisoOperativo));
}

function limiteStockBajo(producto: ProductoOperativo): number {
  const minimo = Number(producto.stock_minimo);
  const guardado = Number(producto.stock_bajo_calculado);
  if (Number.isFinite(guardado) && guardado >= minimo) return guardado;
  const margen = Math.ceil(Number(producto.stock) * 0.1);
  return minimo + Math.max(1, margen);
}

function probabilidadStockBajo(
  stockBidones: number,
  stockFundas: number,
  demandaBidones: number,
  demandaFundas: number,
): number {
  const riesgoBidones = stockBidones <= demandaBidones ? 0.8 : 0.25;
  const riesgoFundas = stockFundas <= demandaFundas ? 0.75 : 0.2;
  return Math.max(riesgoBidones, riesgoFundas);
}

function demandaBaseOperativa(diaSemana: number) {
  switch (diaSemana) {
    case 1:
      return { bidones: 115, fundas: 52 };
    case 2:
      return { bidones: 70, fundas: 40 };
    case 3:
      return { bidones: 104, fundas: 54 };
    case 4:
      return { bidones: 70, fundas: 38 };
    case 5:
      return { bidones: 74, fundas: 42 };
    case 6:
      return { bidones: 127, fundas: 66 };
    case 7:
      return { bidones: 46, fundas: 24 };
    default:
      return { bidones: 75, fundas: 40 };
  }
}

function textoBusqueda(valor: string): string {
  return valor
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

function normalizarClave(valor: string): string {
  return textoBusqueda(valor).replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
}

function esBidon(nombre: string): boolean {
  const texto = textoBusqueda(nombre);
  return texto.includes("bidon") || texto.includes("botellon");
}

function esFunda(nombre: string): boolean {
  return textoBusqueda(nombre).includes("funda");
}

function fechaLocalEcuador(fecha = new Date()): FechaLocal {
  const local = new Date(fecha.getTime() - 5 * 60 * 60 * 1000);
  return {
    anio: local.getUTCFullYear(),
    mes: local.getUTCMonth() + 1,
    dia: local.getUTCDate(),
    hora: local.getUTCHours(),
    diaSemana: diaSemanaDesdeFecha(local),
  };
}

function diaSemanaDesdeFecha(fecha: Date): number {
  const dia = fecha.getUTCDay();
  return dia === 0 ? 7 : dia;
}

function formatoFechaUtc(fecha: Date): string {
  return fecha.toISOString().substring(0, 10);
}

function formatoFechaCorta(fecha: Date): string {
  const meses = [
    "ene",
    "feb",
    "mar",
    "abr",
    "may",
    "jun",
    "jul",
    "ago",
    "sep",
    "oct",
    "nov",
    "dic",
  ];
  return `${fecha.getUTCDate()} ${meses[fecha.getUTCMonth()]}`;
}

function temporadasOperativas(): TemporadaOperativa[] {
  return [
    { nombre: "Inicio de clases", mes: 4, dia: 1 },
    { nombre: "Fiestas de Lago Agrio", mes: 6, dia: 14 },
    { nombre: "Pedidos grandes de septiembre", mes: 9, dia: 1 },
    { nombre: "Pedidos grandes de octubre", mes: 10, dia: 1 },
    { nombre: "Navidad", mes: 12, dia: 8 },
  ];
}

async function validarAutorizacion(
  solicitud: Request,
  cuerpo: SolicitudNotificacion,
): Promise<UsuarioSesion | null> {
  const secreto = Deno.env.get("NOTIFICACIONES_SECRET");
  const autorizacion = solicitud.headers.get("authorization") ?? "";
  const tokenAutorizacion = autorizacion.replace(/^Bearer\s+/i, "").trim();
  const tokenDirecto =
    solicitud.headers.get("x-notificaciones-secret")?.trim() ?? "";
  if (secreto && (tokenAutorizacion === secreto || tokenDirecto === secreto)) {
    return null;
  }

  const tokenSesion = cuerpo.token_sesion?.trim() ?? "";
  if (tokenSesion.length > 0) {
    return await validarSesionApp(tokenSesion);
  }

  throw new Error("No autorizado.");
}

function validarPermisoRevisionOperativa(sesion: UsuarioSesion | null) {
  if (sesion === null) return;
  if (sesion.rol !== "admin" && sesion.rol !== "planta") {
    throw new Error("No autorizado para enviar revision operativa.");
  }
}

async function validarSesionApp(tokenSesion: string): Promise<UsuarioSesion> {
  const urlSupabase = requerirVariable("SUPABASE_URL");
  const llaveServicio = requerirVariable("SUPABASE_SERVICE_ROLE_KEY");
  const respuesta = await fetch(
    `${urlSupabase}/rest/v1/rpc/fn_usuario_sesion`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: llaveServicio,
        Authorization: `Bearer ${llaveServicio}`,
        "Accept-Profile": "usuarios",
        "Content-Profile": "usuarios",
      },
      body: JSON.stringify({ p_session_token: tokenSesion }),
    },
  );

  if (!respuesta.ok) {
    throw new Error("Sesion no autorizada.");
  }

  const filas = (await respuesta.json()) as UsuarioSesion[] | UsuarioSesion;
  const usuario = Array.isArray(filas) ? filas[0] : filas;
  if (!usuario?.id || usuario.activo === false) {
    throw new Error("Sesion no autorizada.");
  }
  return usuario;
}

async function resolverTokens(
  solicitud: SolicitudNotificacion,
  sesion: UsuarioSesion | null = null,
): Promise<string[]> {
  const tokensDirectos = (solicitud.tokens ?? [])
    .map((token) => token.trim())
    .filter((token) => token.length > 0);
  if (tokensDirectos.length > 0) {
    return [...new Set(tokensDirectos)];
  }

  const urlSupabase = requerirVariable("SUPABASE_URL");
  const llaveServicio = requerirVariable("SUPABASE_SERVICE_ROLE_KEY");

  const respuesta = await fetch(
    `${urlSupabase}/rest/v1/rpc/fn_tokens_notificacion`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: llaveServicio,
        Authorization: `Bearer ${llaveServicio}`,
        "Accept-Profile": "usuarios",
        "Content-Profile": "usuarios",
      },
      body: JSON.stringify({
        p_rol: solicitud.rol ?? rolPermitido(solicitud, sesion),
        p_usuario_id:
          solicitud.usuario_id ?? usuarioPermitido(solicitud, sesion),
      }),
    },
  );

  if (!respuesta.ok) {
    throw new Error(
      `No se pudieron consultar tokens: ${await respuesta.text()}`,
    );
  }

  const filas = (await respuesta.json()) as TokenNotificacion[];
  return [
    ...new Set(
      filas
        .map((fila) => fila.token_firebase)
        .filter((token) => token && token.trim().length > 0),
    ),
  ];
}

function rolPermitido(
  solicitud: SolicitudNotificacion,
  sesion: UsuarioSesion | null,
): string | null {
  if (sesion === null) return solicitud.rol ?? null;
  if (sesion.rol === "admin" || sesion.rol === "planta") {
    return solicitud.rol ?? "admin";
  }
  return sesion.rol;
}

function usuarioPermitido(
  solicitud: SolicitudNotificacion,
  sesion: UsuarioSesion | null,
): string | null {
  if (sesion === null) return solicitud.usuario_id ?? null;
  if (sesion.rol === "admin" || sesion.rol === "planta") {
    return solicitud.usuario_id ?? null;
  }
  return sesion.id;
}

async function consultarRegistros<T>(
  esquema: string,
  tabla: string,
  consulta: string,
): Promise<T[]> {
  const urlSupabase = requerirVariable("SUPABASE_URL");
  const llaveServicio = requerirVariable("SUPABASE_SERVICE_ROLE_KEY");
  const respuesta = await fetch(`${urlSupabase}/rest/v1/${tabla}?${consulta}`, {
    headers: {
      apikey: llaveServicio,
      Authorization: `Bearer ${llaveServicio}`,
      "Accept-Profile": esquema,
    },
  });

  if (!respuesta.ok) {
    throw new Error(
      `No se pudo consultar ${esquema}.${tabla}: ${await respuesta.text()}`,
    );
  }
  return (await respuesta.json()) as T[];
}

async function obtenerTokenAccesoFirebase(): Promise<string> {
  const correoCliente = requerirVariable("FIREBASE_CLIENT_EMAIL");
  const llavePrivada = requerirVariable("FIREBASE_PRIVATE_KEY").replaceAll(
    "\\n",
    "\n",
  );
  const ahora = Math.floor(Date.now() / 1000);
  const encabezado = { alg: "RS256", typ: "JWT" };
  const carga = {
    iss: correoCliente,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: ahora,
    exp: ahora + 3600,
  };

  const textoFirma = `${base64UrlJson(encabezado)}.${base64UrlJson(carga)}`;
  const llave = await importarLlavePrivada(llavePrivada);
  const firma = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    llave,
    new TextEncoder().encode(textoFirma),
  );
  const jwt = `${textoFirma}.${base64UrlBytes(new Uint8Array(firma))}`;

  const respuesta = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!respuesta.ok) {
    throw new Error(
      `Firebase no entrego token de acceso: ${await respuesta.text()}`,
    );
  }

  const json = (await respuesta.json()) as { access_token?: string };
  if (!json.access_token) {
    throw new Error("Firebase no devolvio access_token.");
  }
  return json.access_token;
}

async function enviarNotificacionFirebase({
  token,
  titulo,
  cuerpo,
  datos,
  tokenAcceso,
}: {
  token: string;
  titulo: string;
  cuerpo: string;
  datos: Record<string, string | number | boolean | null>;
  tokenAcceso: string;
}) {
  const proyectoFirebase = requerirVariable("FIREBASE_PROJECT_ID");
  const datosTexto = Object.fromEntries(
    Object.entries(datos).map(([clave, valor]) => [clave, String(valor ?? "")]),
  );

  const respuesta = await fetch(
    `https://fcm.googleapis.com/v1/projects/${proyectoFirebase}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${tokenAcceso}`,
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: titulo, body: cuerpo },
          data: datosTexto,
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "high_importance_channel",
              sound: "default",
            },
          },
        },
      }),
    },
  );

  if (respuesta.ok) {
    return { token, ok: true };
  }

  return {
    token,
    ok: false,
    error: await respuesta.text(),
  };
}

async function desactivarTokensInvalidos(
  resultados: Array<{ token: string; ok: boolean; error?: string }>,
) {
  const invalidos = resultados
    .filter((resultado) => !resultado.ok && tokenFirebaseInvalido(resultado))
    .map((resultado) => resultado.token);
  if (invalidos.length === 0) return;

  await Promise.allSettled(
    [...new Set(invalidos)].map((token) => desactivarTokenDispositivo(token)),
  );
}

function tokenFirebaseInvalido(resultado: {
  token: string;
  ok: boolean;
  error?: string;
}) {
  const error = resultado.error ?? "";
  return (
    error.includes("UNREGISTERED") ||
    error.includes("registration-token-not-registered") ||
    error.includes("Requested entity was not found") ||
    error.includes("INVALID_ARGUMENT")
  );
}

async function desactivarTokenDispositivo(token: string) {
  const urlSupabase = requerirVariable("SUPABASE_URL");
  const llaveServicio = requerirVariable("SUPABASE_SERVICE_ROLE_KEY");
  await fetch(
    `${urlSupabase}/rest/v1/tokens_dispositivo?token_firebase=eq.${encodeURIComponent(token)}`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        apikey: llaveServicio,
        Authorization: `Bearer ${llaveServicio}`,
        "Accept-Profile": "usuarios",
        "Content-Profile": "usuarios",
      },
      body: JSON.stringify({ activo: false }),
    },
  );
}

async function importarLlavePrivada(pem: string): Promise<CryptoKey> {
  const contenido = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binario = Uint8Array.from(atob(contenido), (caracter) =>
    caracter.charCodeAt(0),
  );

  return await crypto.subtle.importKey(
    "pkcs8",
    binario.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function base64UrlJson(valor: unknown): string {
  return base64UrlBytes(new TextEncoder().encode(JSON.stringify(valor)));
}

function base64UrlBytes(bytes: Uint8Array): string {
  let binario = "";
  for (const byte of bytes) {
    binario += String.fromCharCode(byte);
  }
  return btoa(binario)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function requerirVariable(nombre: string): string {
  const valor = Deno.env.get(nombre);
  if (!valor) throw new Error(`Falta configurar ${nombre}.`);
  return valor;
}

function respuestaJson(datos: unknown, estado = 200): Response {
  return new Response(JSON.stringify(datos), {
    status: estado,
    headers: {
      ...encabezadosCors,
      "Content-Type": "application/json",
    },
  });
}
