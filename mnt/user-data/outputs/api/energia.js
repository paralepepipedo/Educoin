// ============================================
// api/energia.js — Sistema de energía
// POST /api/energia { action: 'recargar' }
// POST /api/energia { action: 'generar_monedas' }
// ============================================

import { query, getPerfil, agregarMonedas, res, resError, verificarAuth, getConfigEconomia } from '../lib/neon.js';

const HORA_RESET_CHILE = 20;
const MONEDAS_POR_CICLO = 5; // cada 5 minutos con energía activa

function horaChile() {
  return new Date(new Date().toLocaleString('en-US', { timeZone: 'America/Santiago' }));
}

export default async function handler(request) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204 });

  const auth = await verificarAuth(request);
  if (!auth.ok) return resError('No autorizado', 401);

  const perfil = await getPerfil(auth.clerkId);
  if (!perfil) return resError('Perfil no encontrado', 404);

  const body   = await request.json().catch(() => ({}));
  const action = body.action;

  // ── Recargar energía ──────────────────────
  if (action === 'recargar') {
    const ahora        = horaChile();
    const ultimaRecarga = new Date(
      new Date(perfil.ultima_recarga).toLocaleString('en-US', { timeZone: 'America/Santiago' })
    );

    const mismaFecha =
      ahora.getFullYear() === ultimaRecarga.getFullYear() &&
      ahora.getMonth()    === ultimaRecarga.getMonth()    &&
      ahora.getDate()     === ultimaRecarga.getDate();

    // No recargar si ya se recargó hoy después de las 20:00
    if (mismaFecha && ahora.getHours() < HORA_RESET_CHILE) {
      return res({ recargada: false, mensaje: 'Energía recargada hoy. Próxima recarga a las 20:00.' });
    }
    if (mismaFecha && ultimaRecarga.getHours() >= HORA_RESET_CHILE) {
      return res({ recargada: false, mensaje: 'Ya se recargó hoy después de las 20:00.' });
    }

    // Recargar y actualizar racha de días
    const hoyFecha = `${ahora.getFullYear()}-${ahora.getMonth()+1}-${ahora.getDate()}`;
    const ayerFecha = new Date(ahora);
    ayerFecha.setDate(ayerFecha.getDate() - 1);
    const ayerStr = `${ayerFecha.getFullYear()}-${ayerFecha.getMonth()+1}-${ayerFecha.getDate()}`;

    // Racha: si el último login fue ayer, aumentar. Si fue antes, resetear.
    let nuevaRacha = perfil.racha_dias;
    if (perfil.ultimo_login) {
      const ultimoLogin = new Date(perfil.ultimo_login).toISOString().split('T')[0];
      if (ultimoLogin === ayerStr) nuevaRacha += 1;
      else if (ultimoLogin !== hoyFecha) nuevaRacha = 1;
    } else {
      nuevaRacha = 1;
    }

    await query(
      `UPDATE perfiles
       SET energia_actual = energia_max,
           ultima_recarga = NOW(),
           ultimo_login   = CURRENT_DATE,
           racha_dias     = $1,
           updated_at     = NOW()
       WHERE id = $2`,
      [nuevaRacha, perfil.id]
    );

    // Bonus por racha
    const config = await getConfigEconomia();
    let bonusRacha = null;
    if (nuevaRacha === 7)  { await agregarMonedas(perfil.id, config.racha_7_dias  || 500,  '🔥 Bonus: 7 días de racha'); bonusRacha = 500; }
    if (nuevaRacha === 30) { await agregarMonedas(perfil.id, config.racha_30_dias || 2000, '👑 Bonus: 30 días de racha'); bonusRacha = 2000; }

    return res({
      recargada:    true,
      energia_max:  perfil.energia_max,
      racha_dias:   nuevaRacha,
      bonus_racha:  bonusRacha,
      mensaje:      '⚡ ¡Energía recargada al máximo!',
    });
  }

  // ── Generación pasiva de monedas ──────────
  if (action === 'generar_monedas') {
    if (perfil.energia_actual <= 0) {
      return res({ monedas_generadas: 0, energia_restante: 0, mensaje: 'Sin energía' });
    }

    // Restar 5 de energía por ciclo
    const nuevaEnergia = Math.max(0, perfil.energia_actual - 5);
    await query(
      `UPDATE perfiles SET energia_actual = $1, updated_at = NOW() WHERE id = $2`,
      [nuevaEnergia, perfil.id]
    );

    // Dar monedas pasivas
    await agregarMonedas(perfil.id, MONEDAS_POR_CICLO, '⚡ Monedas pasivas por energía activa');

    return res({
      monedas_generadas: MONEDAS_POR_CICLO,
      energia_restante:  nuevaEnergia,
    });
  }

  return resError('Acción no reconocida');
}
