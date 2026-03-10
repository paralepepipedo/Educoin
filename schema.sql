-- ============================================
-- EDUCOINS — Schema SQL para Neon
-- Ejecutar en: console.neon.tech → SQL Editor
-- ============================================

-- ÍNDICE
-- 1. Extensiones
-- 2. Tabla: perfiles
-- 3. Tabla: evaluaciones
-- 4. Tabla: tareas
-- 5. Tabla: misiones_diarias
-- 6. Tabla: duelos
-- 7. Tabla: transacciones
-- 8. Tabla: objetivos_mensuales
-- 9. Tabla: config_economia
-- 10. Tabla: logros
-- 11. Tabla: logros_usuario
-- 12. Índices de rendimiento
-- 13. Datos iniciales (config_economia)

-- ============================================
-- 1. EXTENSIONES
-- ============================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================
-- 2. PERFILES
-- ============================================
CREATE TABLE IF NOT EXISTS perfiles (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  clerk_id        TEXT        UNIQUE NOT NULL,          -- ID de Clerk Auth
  nombre          TEXT        NOT NULL,
  email           TEXT        UNIQUE NOT NULL,
  grado_ingreso   SMALLINT    NOT NULL CHECK (grado_ingreso BETWEEN 1 AND 8),
  anio_ingreso    SMALLINT    NOT NULL DEFAULT EXTRACT(YEAR FROM NOW()),
  avatar_base     TEXT        NOT NULL DEFAULT 'conejo', -- conejo|oso|zorro|pinguino|gato|perro|pajaro
  accesorios      TEXT[]      DEFAULT '{}',
  nivel           SMALLINT    NOT NULL DEFAULT 1,
  xp              INTEGER     NOT NULL DEFAULT 0,
  monedas         INTEGER     NOT NULL DEFAULT 100,     -- 100 de bienvenida
  energia_actual  SMALLINT    NOT NULL DEFAULT 100,
  energia_max     SMALLINT    NOT NULL DEFAULT 100,
  ultima_recarga  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  racha_dias      SMALLINT    NOT NULL DEFAULT 0,
  ultimo_login    DATE,
  telegram_chat_id TEXT,
  rol             TEXT        NOT NULL DEFAULT 'alumno' CHECK (rol IN ('alumno','admin')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 3. EVALUACIONES (Calendario)
-- ============================================
CREATE TABLE IF NOT EXISTS evaluaciones (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  asignatura           TEXT        NOT NULL CHECK (asignatura IN (
                         'Matematicas','Lenguaje','Historia','Ciencias',
                         'Ingles','Ed. Fisica','Musica','Artes','Tecnologia'
                       )),
  fecha_evaluacion     DATE        NOT NULL,
  contenidos           TEXT,
  nota_esperada        NUMERIC(3,1) CHECK (nota_esperada BETWEEN 1.0 AND 7.0),
  rango_min            NUMERIC(3,1),
  rango_max            NUMERIC(3,1),
  nota_obtenida        NUMERIC(3,1) CHECK (nota_obtenida BETWEEN 1.0 AND 7.0),
  estado               TEXT        NOT NULL DEFAULT 'pendiente'
                         CHECK (estado IN ('pendiente','estudiado','rendida','nota_ingresada')),
  foto_url             TEXT,                            -- URL en almacenamiento, NO base64
  recompensa_entregada BOOLEAN     NOT NULL DEFAULT FALSE,
  alerta_enviada_at    TIMESTAMPTZ,                     -- última alerta Telegram enviada
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 4. TAREAS
-- ============================================
CREATE TABLE IF NOT EXISTS tareas (
  id                          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                     UUID        NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  fecha                       DATE        NOT NULL DEFAULT CURRENT_DATE,
  asignatura                  TEXT        NOT NULL,
  contenido_subido            TEXT,
  foto_url                    TEXT,
  es_correcta                 BOOLEAN,
  porcentaje_obtenido         SMALLINT    DEFAULT 100,
  intentos_fallados_consecutivos SMALLINT DEFAULT 0,
  ayudas_usadas_hoy           SMALLINT    DEFAULT 0,
  recompensa_entregada        BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 5. MISIONES DIARIAS
-- ============================================
CREATE TABLE IF NOT EXISTS misiones_diarias (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  fecha            DATE        NOT NULL DEFAULT CURRENT_DATE,
  tipo_mision      TEXT        NOT NULL,
  descripcion      TEXT        NOT NULL,
  icono            TEXT        NOT NULL DEFAULT '🎯',
  completada       BOOLEAN     NOT NULL DEFAULT FALSE,
  recompensa_monedas INTEGER   NOT NULL DEFAULT 50,
  completada_at    TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, fecha, tipo_mision)
);

-- ============================================
-- 6. DUELOS
-- ============================================
CREATE TABLE IF NOT EXISTS duelos (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  retador_id       UUID        NOT NULL REFERENCES perfiles(id),
  retado_id        UUID        NOT NULL REFERENCES perfiles(id),
  asignatura       TEXT        NOT NULL,
  preguntas        JSONB       NOT NULL DEFAULT '[]',   -- [{pregunta, opciones, correcta}]
  respuestas_retador JSONB     DEFAULT '[]',
  respuestas_retado  JSONB     DEFAULT '[]',
  puntaje_retador  SMALLINT    DEFAULT 0,
  puntaje_retado   SMALLINT    DEFAULT 0,
  monedas_apostadas INTEGER    DEFAULT 0,
  estado           TEXT        NOT NULL DEFAULT 'pendiente'
                     CHECK (estado IN ('pendiente','aceptado','en_juego','finalizado','rechazado')),
  ganador_id       UUID        REFERENCES perfiles(id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finalizado_at    TIMESTAMPTZ
);

-- ============================================
-- 7. TRANSACCIONES DE MONEDAS
-- ============================================
CREATE TABLE IF NOT EXISTS transacciones (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  tipo        TEXT        NOT NULL CHECK (tipo IN ('ganancia','gasto')),
  monto       INTEGER     NOT NULL CHECK (monto > 0),
  concepto    TEXT        NOT NULL,
  referencia_id UUID,                                   -- ID de la misión/tarea/duelo
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 8. OBJETIVOS MENSUALES
-- ============================================
CREATE TABLE IF NOT EXISTS objetivos_mensuales (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID        NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  mes            SMALLINT    NOT NULL CHECK (mes BETWEEN 1 AND 12),
  anio           SMALLINT    NOT NULL,
  descripcion    TEXT        NOT NULL,
  dificultad     TEXT        NOT NULL DEFAULT 'alta' CHECK (dificultad IN ('media','alta','epica')),
  costo_monedas  INTEGER     NOT NULL DEFAULT 5000,
  estado         TEXT        NOT NULL DEFAULT 'pendiente'
                   CHECK (estado IN ('pendiente','aprobado','entregado')),
  giftcard_code  TEXT,
  solicitado_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  aprobado_at    TIMESTAMPTZ,
  entregado_at   TIMESTAMPTZ
);

-- ============================================
-- 9. CONFIG ECONOMÍA (editable desde /admin/)
-- ============================================
CREATE TABLE IF NOT EXISTS config_economia (
  clave       TEXT        PRIMARY KEY,
  valor       NUMERIC     NOT NULL,
  descripcion TEXT        NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 10. LOGROS
-- ============================================
CREATE TABLE IF NOT EXISTS logros (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  clave       TEXT        UNIQUE NOT NULL,
  nombre      TEXT        NOT NULL,
  descripcion TEXT        NOT NULL,
  icono       TEXT        NOT NULL DEFAULT '🏆',
  xp_premio   INTEGER     NOT NULL DEFAULT 100,
  monedas_premio INTEGER  NOT NULL DEFAULT 50
);

-- ============================================
-- 11. LOGROS POR USUARIO
-- ============================================
CREATE TABLE IF NOT EXISTS logros_usuario (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  logro_id    UUID        NOT NULL REFERENCES logros(id),
  obtenido_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, logro_id)
);

-- ============================================
-- 12. ÍNDICES DE RENDIMIENTO
-- ============================================
CREATE INDEX IF NOT EXISTS idx_evaluaciones_user_fecha  ON evaluaciones(user_id, fecha_evaluacion);
CREATE INDEX IF NOT EXISTS idx_evaluaciones_estado       ON evaluaciones(estado);
CREATE INDEX IF NOT EXISTS idx_tareas_user_fecha         ON tareas(user_id, fecha);
CREATE INDEX IF NOT EXISTS idx_misiones_user_fecha       ON misiones_diarias(user_id, fecha);
CREATE INDEX IF NOT EXISTS idx_transacciones_user        ON transacciones(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_duelos_retador            ON duelos(retador_id);
CREATE INDEX IF NOT EXISTS idx_duelos_retado             ON duelos(retado_id);
CREATE INDEX IF NOT EXISTS idx_perfiles_clerk            ON perfiles(clerk_id);
CREATE INDEX IF NOT EXISTS idx_perfiles_monedas          ON perfiles(monedas DESC);  -- para ranking rápido

-- ============================================
-- 13. DATOS INICIALES — CONFIG ECONOMÍA
-- ============================================
INSERT INTO config_economia (clave, valor, descripcion) VALUES
  ('mision_completada',          50,   'Monedas por completar 1 misión diaria'),
  ('bonus_8_misiones',          200,   'Bonus extra al completar las 8 misiones del día'),
  ('tarea_correcta',            100,   'Monedas por tarea correcta (100%)'),
  ('tarea_con_error',            80,   'Monedas por tarea con error leve (80%)'),
  ('duelo_ganado',              150,   'Monedas por ganar un duelo'),
  ('juego_completado',           80,   'Monedas base por completar un juego'),
  ('bonus_multiplicacion',       80,   'Monedas extra al acertar el bonus de multiplicación'),
  ('nota_7_exacto',             300,   'Monedas por sacar 7.0 exacto en evaluación'),
  ('nota_en_rango',             150,   'Monedas por nota dentro del rango esperado'),
  ('nota_fuera_rango',            0,   'Monedas por nota fuera del rango (sin recompensa)'),
  ('racha_7_dias',              500,   'Bonus por completar 7 días seguidos activo'),
  ('racha_30_dias',            2000,   'Bonus por completar 30 días seguidos activo'),
  ('bienvenida',                100,   'Monedas de bienvenida al registrarse')
ON CONFLICT (clave) DO NOTHING;

-- ============================================
-- 14. TABLA: TIENDA ITEMS (catálogo admin)
-- ============================================
CREATE TABLE IF NOT EXISTS tienda_items (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  categoria   TEXT        NOT NULL CHECK (categoria IN ('avatares','accesorios','ventajas','decoracion')),
  emoji       TEXT        NOT NULL,
  nombre      TEXT        NOT NULL,
  descripcion TEXT        NOT NULL,
  precio      INTEGER     NOT NULL CHECK (precio > 0),
  disponible  BOOLEAN     NOT NULL DEFAULT TRUE,
  orden       SMALLINT    NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 15. TABLA: TIENDA COMPRAS (historial por usuario)
-- ============================================
CREATE TABLE IF NOT EXISTS tienda_compras (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  item_id      UUID        NOT NULL REFERENCES tienda_items(id),
  precio_pagado INTEGER    NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, item_id)
);

-- ============================================
-- 16. TABLA: JUEGOS PARTIDAS (registro de plays)
-- ============================================
CREATE TABLE IF NOT EXISTS juegos_partidas (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID        NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  juego_id        TEXT        NOT NULL,
  puntos          INTEGER     NOT NULL DEFAULT 0,
  duracion_seg    INTEGER     NOT NULL DEFAULT 0,
  monedas_ganadas INTEGER     NOT NULL DEFAULT 0,
  completado      BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_juegos_partidas_user ON juegos_partidas(user_id, created_at DESC);

-- ============================================
-- 17. TABLA: MISIONES BANCO (administrable desde /admin/)
-- ============================================
CREATE TABLE IF NOT EXISTS misiones_banco (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo            TEXT        UNIQUE NOT NULL,
  descripcion     TEXT        NOT NULL,
  icono           TEXT        NOT NULL DEFAULT '🎯',
  recompensa_base INTEGER     NOT NULL DEFAULT 50,
  activo          BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 18. DATOS INICIALES: TIENDA ITEMS
-- ============================================
INSERT INTO tienda_items (categoria, emoji, nombre, descripcion, precio, orden) VALUES
  ('avatares',   '🦄', 'UNICORNIO',     'Avatar mítico exclusivo',               500,  1),
  ('avatares',   '🐲', 'DRAGÓN',        'Avatar legendario',                    1000,  2),
  ('avatares',   '👾', 'ALIEN PRO',     'Avatar de otro mundo',                  750,  3),
  ('avatares',   '🤖', 'ROBOT 3000',    'Avatar futurista',                      800,  4),
  ('ventajas',   '⚡', 'ENERGÍA x2',    'Doble energía por 1 día',               300,  5),
  ('ventajas',   '🎯', 'MISIÓN EXTRA',  'Misión bonus de +150 monedas',          200,  6),
  ('ventajas',   '🛡️', 'ESCUDO DUELO',  'Protege racha si pierdes duelo',        400,  7),
  ('ventajas',   '🔥', 'RACHA SEGURA',  'Mantén racha por 1 falta',              500,  8),
  ('decoracion', '👑', 'CORONA DORADA', 'Marco de corona en tu perfil',         1500,  9),
  ('decoracion', '🌟', 'AURA ESTELAR',  'Brillo animado en tu avatar',          2000, 10),
  ('decoracion', '🎭', 'MARCO DUELIST', 'Marco especial de duelos',              800, 11),
  ('decoracion', '💎', 'CRISTAL VIP',   'Insignia VIP en tu nombre',            3000, 12)
ON CONFLICT DO NOTHING;

-- ============================================
-- 19. DATOS INICIALES: MISIONES BANCO
-- ============================================
INSERT INTO misiones_banco (tipo, descripcion, icono, recompensa_base) VALUES
  ('jugar_juegos',         'Jugar 3 juegos educativos',                  '🎮', 80),
  ('trivia_completar',     'Completar una trivia de Historia',           '🏛️', 60),
  ('subir_tarea',          'Subir una tarea de Matemáticas',             '📝', 100),
  ('tabla_multiplicar',    'Practicar la tabla de multiplicar (×7)',     '✖️', 50),
  ('problema_texto',       'Resolver 3 problemas de texto correctos',   '🔢', 90),
  ('ganar_duelo',          'Ganar un duelo contra otro alumno',          '⚔️', 120),
  ('marcar_estudiado',     'Marcar una evaluación como "estudiada"',    '📅', 40),
  ('sinonimos',            'Completar el juego de sinónimos',            '🔤', 60),
  ('memoria',              'Completar el juego de memoria',              '🃏', 70),
  ('trivia_chile',         'Responder 5 preguntas de Trivia Chile',      '🇨🇱', 80),
  ('tarea_ingles',         'Completar una actividad de Inglés',          '🇬🇧', 60),
  ('revisar_ayudas',       'Visitar la sección de material de apoyo',   '📚', 30),
  ('coinclik',             'Alcanzar 500 puntos en CoinClik',            '💰', 90),
  ('subir_nota',           'Registrar la nota de una prueba rendida',   '⭐', 70),
  ('multiplicacion_bonus', 'Acertar 3 bonus de multiplicación seguidos','⚡', 100)
ON CONFLICT (tipo) DO NOTHING;

-- ============================================
-- 20. LOGROS INICIALES
-- ============================================
INSERT INTO logros (clave, nombre, descripcion, icono, xp_premio, monedas_premio) VALUES
  ('primer_login',        'Primeros Pasos',       'Iniciaste sesión por primera vez',                     '👋', 50,  25),
  ('primera_mision',      'Misionero',            'Completaste tu primera misión diaria',                 '🎯', 100, 50),
  ('8_misiones_dia',      'Imparable',            'Completaste las 8 misiones en un día',                 '⚡', 200, 100),
  ('racha_7',             'Semana Perfecta',      '7 días seguidos activo en la plataforma',              '🔥', 300, 150),
  ('racha_30',            'Leyenda del Mes',      '30 días seguidos activo',                              '👑', 1000, 500),
  ('primer_7',            'Nota Máxima',          'Obtuviste un 7.0 en una evaluación',                   '⭐', 250, 200),
  ('primer_duelo',        'Retador',              'Participaste en tu primer duelo',                      '⚔️', 100, 50),
  ('duelo_ganado',        'Victorioso',           'Ganaste tu primer duelo',                              '🏆', 200, 100),
  ('5_juegos',            'Gamer Educativo',      'Jugaste 5 juegos educativos',                          '🎮', 150, 75),
  ('nivel_10',            'Estudiante Pro',       'Alcanzaste el nivel 10',                               '🚀', 500, 250),
  ('nivel_20',            'Maestro',              'Alcanzaste el nivel 20',                               '💎', 1000, 500)
ON CONFLICT (clave) DO NOTHING;
