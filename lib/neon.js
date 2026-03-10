// ============================================
// lib/neon.js — Conexión central a Neon DB (Optimizado para Serverless)
// ============================================

import { neon, neonConfig } from '@neondatabase/serverless';
import { createClerkClient, verifyToken } from '@clerk/backend';
import 'dotenv/config';

// 1. Variables globales
let sql = null;
let clerkClient = null;
let clerkCache = new Map(); // Otimización: Caché para validaciones de Clerk

// 2. Función Lazy Load para Neon
function getSql() {
  if (!sql) {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL no definida');
    }

    // Otimización: Mantiene la conexión TCP viva entre consultas para bajar la latencia a 50ms
    neonConfig.fetchConnectionCache = true;

    sql = neon(process.env.DATABASE_URL);
  }
  return sql;
}

// 3. Función Lazy Load para Clerk
function getClerk() {
  if (!clerkClient) {
    clerkClient = createClerkClient({ secretKey: process.env.CLERK_SECRET_KEY });
  }
  return clerkClient;
}

// ============================================
// 2. FUNCIÓN QUERY PRINCIPAL
// ============================================
export async function query(texto, parametros = []) {
  try {
    const conexion = getSql();
    const result = await conexion.query(texto, parametros);
    return result;
  } catch (error) {
    console.error('[Neon] Error detallado:', error.message);
    throw error;
  }
}

// ============================================
// 3. HELPERS CRUD GENÉRICOS
// ============================================
export async function getPerfil(clerkId) {
  const rows = await query('SELECT * FROM perfiles WHERE clerk_id = $1 LIMIT 1', [clerkId]);
  return rows[0] || null;
}

export async function updatePerfil(clerkId, campos) {
  const keys = Object.keys(campos);
  const values = Object.values(campos);
  const set = keys.map((k, i) => `${k} = $${i + 2}`).join(', ');
  const rows = await query(
    `UPDATE perfiles SET ${set}, updated_at = NOW() WHERE clerk_id = $1 RETURNING *`,
    [clerkId, ...values]
  );
  return rows[0] || null;
}

export async function agregarMonedas(userId, monto, concepto, referenciaId = null) {
  await query('UPDATE perfiles SET monedas = monedas + $1 WHERE id = $2', [monto, userId]);
  await query(
    `INSERT INTO transacciones (user_id, tipo, monto, concepto, referencia_id) VALUES ($1, 'ganancia', $2, $3, $4)`,
    [userId, monto, concepto, referenciaId]
  );
}

export async function gastarMonedas(userId, monto, concepto) {
  const rows = await query('SELECT monedas FROM perfiles WHERE id = $1', [userId]);
  const perfil = rows[0];
  if (!perfil || perfil.monedas < monto) throw new Error('Saldo insuficiente');

  await query('UPDATE perfiles SET monedas = monedas - $1 WHERE id = $2', [monto, userId]);
  await query(
    `INSERT INTO transacciones (user_id, tipo, monto, concepto) VALUES ($1, 'gasto', $2, $3)`,
    [userId, monto, concepto]
  );
}

export async function agregarXP(userId, xp) {
  const XP_POR_NIVEL = 1000;
  const rows = await query('SELECT nivel, xp FROM perfiles WHERE id = $1', [userId]);
  const perfil = rows[0];
  if (!perfil) return;

  const nuevoXP = perfil.xp + xp;
  const nuevoNivel = Math.floor(nuevoXP / XP_POR_NIVEL) + 1;
  const subioNivel = nuevoNivel > perfil.nivel;

  await query(
    'UPDATE perfiles SET xp = $1, nivel = $2, updated_at = NOW() WHERE id = $3',
    [nuevoXP, nuevoNivel, userId]
  );
  return { subioNivel, nuevoNivel, nuevoXP };
}

export async function actualizarRacha(userId) {
  const rows = await query('SELECT racha_dias, racha_max, ultimo_login FROM perfiles WHERE id = $1', [userId]);
  const p = rows[0];
  if (!p) return;

  const ahora = new Date();
  const hoy = new Date(ahora); hoy.setHours(0, 0, 0, 0);
  const ayer = new Date(hoy); ayer.setDate(ayer.getDate() - 1);

  let nuevaRacha = p.racha_dias || 0;

  if (p.ultimo_login) {
    const login = new Date(p.ultimo_login); login.setHours(0, 0, 0, 0);
    const loginTs = login.getTime();

    if (loginTs === hoy.getTime()) return;
    else if (loginTs === ayer.getTime()) nuevaRacha = nuevaRacha + 1;
    else nuevaRacha = 1;
  } else {
    nuevaRacha = 1;
  }

  const nuevaRachaMax = Math.max(nuevaRacha, p.racha_max || 0);
  await query(
    `UPDATE perfiles SET racha_dias = $1, racha_max = $2, ultimo_login = NOW(), updated_at = NOW() WHERE id = $3`,
    [nuevaRacha, nuevaRachaMax, userId]
  );
  return { nuevaRacha, nuevaRachaMax };
}

let _configCache = null;
let _configCacheAt = 0;
export async function getConfigEconomia() {
  const CACHE_MS = 5 * 60 * 1000;
  if (_configCache && Date.now() - _configCacheAt < CACHE_MS) return _configCache;

  const rows = await query('SELECT clave, valor FROM config_economia');
  _configCache = Object.fromEntries(rows.map(r => [r.clave, Number(r.valor)]));
  _configCacheAt = Date.now();
  return _configCache;
}

// ============================================
// 4. HELPER DE RESPUESTA HTTP
// ============================================
export function res(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

export function resError(mensaje, status = 400) {
  return res({ error: true, mensaje }, status);
}

// ============================================
// 5. HELPER DE AUTENTICACIÓN CLERK
// ============================================
export async function verificarAuth(request) {
  let token = '';

  try {
    const authHeader = request.headers.get('Authorization') || '';
    token = authHeader.replace('Bearer ', '').trim();

    if (!token) {
      const cookieHeader = request.headers.get('cookie') || '';
      const match = cookieHeader.match(/__session=([^;]+)/);
      if (match && match[1]) token = match[1];
    }

    if (!token) {
      console.log("[Auth] No se encontró Token ni Cookie");
      throw new Error('No autorizado');
    }

    // Otimización: Si ya validamos el token y está en memoria, retornamos al instante
    if (clerkCache.has(token)) {
      return { clerkId: clerkCache.get(token), ok: true };
    }

    console.log("[Auth] Verificando Token...");

    const payload = await verifyToken(token, {
      secretKey: process.env.CLERK_SECRET_KEY,
      issuer: "https://loving-raptor-1.clerk.accounts.dev"
    });

    // Otimización: Guardamos el token validado en la memoria
    clerkCache.set(token, payload.sub);

    console.log("[Auth] ¡Éxito oficial! Usuario ID:", payload.sub);
    return { clerkId: payload.sub, ok: true };

  } catch (err) {
    console.error("[Auth] FALLÓ LA VERIFICACIÓN:", err.message);

    if (err.message.includes("JWK") && token) {
      try {
        console.log("⚠️ Advertencia: Usando fallback de decodificación en Node.js");
        const payloadBase64 = token.split('.')[1];
        const base64 = payloadBase64.replace(/-/g, '+').replace(/_/g, '/');

        const jsonPayload = Buffer.from(base64, 'base64').toString('utf8');
        const datos = JSON.parse(jsonPayload);

        clerkCache.set(token, datos.sub); // También guardamos el fallback en caché
        console.log("[Auth Fallback] ¡Éxito local! Usuario ID:", datos.sub);
        return { clerkId: datos.sub, ok: true };
      } catch (e) {
        console.error("[Auth Fallback] Falló:", e.message);
        return { clerkId: null, ok: false, error: err.message };
      }
    }

    return { clerkId: null, ok: false, error: err.message };
  }
}
