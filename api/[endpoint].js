import 'dotenv/config';

export default async function handler(req, res) {
  const urlParts = req.url.split('?')[0].split('/');
  const endpoint = urlParts[urlParts.length - 1];

  if (!endpoint || endpoint === 'api') {
    return res.status(400).json({ error: true, mensaje: 'Endpoint vacío' });
  }

  try {
    const { default: apiHandler } = await import(`../src_api/${endpoint}.js`);

    const protocol = req.headers['x-forwarded-proto'] || 'http';
    const host = req.headers['x-forwarded-host'] || req.headers.host;
    const url = new URL(req.url, `${protocol}://${host}`);

    // ==========================================
    // MAGIA DE COOKIES Y HEADERS PARA CLERK
    // ==========================================
    const customHeaders = new Headers();

    // 1. Pasar todos los headers que manda el navegador (incluyendo Authorization si existe)
    for (const [key, value] of Object.entries(req.headers)) {
      customHeaders.set(key, value);
    }

    // 2. FORZAR LA INYECCIÓN DE LA COOKIE
    // Vercel en Node expone req.headers.cookie
    if (req.headers.cookie) {
      customHeaders.set('cookie', req.headers.cookie);
    }

    // Crear el Request simulando el entorno local de tu antiguo server-2.js
    const webReq = new Request(url, {
      method: req.method,
      headers: customHeaders,
      body: req.method !== 'GET' && req.method !== 'HEAD' && req.body ? JSON.stringify(req.body) : undefined
    });

    const response = await apiHandler(webReq);

    // Enviar respuesta al frontend
    if (response instanceof Response) {
      const data = await response.json();
      return res.status(response.status || 200).json(data);
    } else {
      return res.status(200).json(response);
    }

  } catch (error) {
    console.error(`[API ERROR CRÍTICO] Fallo en ${endpoint}:`, error);
    if (!res.headersSent) {
      return res.status(500).json({ error: true, mensaje: error.message });
    }
  }
}
