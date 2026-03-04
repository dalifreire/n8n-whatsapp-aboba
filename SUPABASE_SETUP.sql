-- SQL para criar tabelas no Supabase
-- Execute este script no SQL Editor do Supabase Dashboard

-- Criar schema 'abo' se não existir
CREATE SCHEMA IF NOT EXISTS abo;

-- ============================================
-- TABELA DE CONVERSAS
-- ============================================
CREATE TABLE IF NOT EXISTS abo.conversas (
  id BIGSERIAL PRIMARY KEY,
  telefone VARCHAR(20) NOT NULL,
  nome VARCHAR(255),
  mensagem TEXT NOT NULL,
  resposta_ia TEXT NOT NULL,
  contexto_rag JSONB,
  data_hora TIMESTAMPTZ DEFAULT NOW(),
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_conversas_telefone ON abo.conversas(telefone);
CREATE INDEX IF NOT EXISTS idx_conversas_data_hora ON abo.conversas(data_hora DESC);
CREATE INDEX IF NOT EXISTS idx_conversas_criado_em ON abo.conversas(criado_em DESC);

-- ============================================
-- TABELA DE USUÁRIOS
-- ============================================
CREATE TABLE IF NOT EXISTS abo.usuarios (
  id BIGSERIAL PRIMARY KEY,
  telefone VARCHAR(20) UNIQUE NOT NULL,
  nome VARCHAR(255),
  email VARCHAR(255),
  primeira_interacao TIMESTAMPTZ DEFAULT NOW(),
  ultima_interacao TIMESTAMPTZ DEFAULT NOW(),
  total_interacoes INT DEFAULT 1,
  metadados JSONB,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_usuarios_telefone ON abo.usuarios(telefone);
CREATE INDEX IF NOT EXISTS idx_usuarios_email ON abo.usuarios(email);
CREATE INDEX IF NOT EXISTS idx_usuarios_ultima_interacao ON abo.usuarios(ultima_interacao DESC);

-- ============================================
-- TABELA DE AVALIAÇÕES (satisfação do usuário)
-- ============================================
CREATE TABLE IF NOT EXISTS abo.avaliacoes (
  id BIGSERIAL PRIMARY KEY,
  id_conversa BIGINT REFERENCES abo.conversas(id) ON DELETE CASCADE,
  nota INT CHECK (nota >= 1 AND nota <= 5),
  comentario TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_avaliacoes_conversa ON abo.avaliacoes(id_conversa);
CREATE INDEX IF NOT EXISTS idx_avaliacoes_nota ON abo.avaliacoes(nota);
CREATE INDEX IF NOT EXISTS idx_avaliacoes_criado_em ON abo.avaliacoes(criado_em DESC);

-- ============================================
-- TABELA DE ESCALAÇÕES (atendimento humano)
-- ============================================
CREATE TABLE IF NOT EXISTS abo.escalacoes (
  id BIGSERIAL PRIMARY KEY,
  id_conversa BIGINT REFERENCES abo.conversas(id) ON DELETE CASCADE,
  telefone VARCHAR(20) NOT NULL,
  motivo TEXT,
  status VARCHAR(50) DEFAULT 'pendente',
  atribuido_a VARCHAR(255),
  resolvido_em TIMESTAMPTZ,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_escalacoes_conversa ON abo.escalacoes(id_conversa);
CREATE INDEX IF NOT EXISTS idx_escalacoes_status ON abo.escalacoes(status);
CREATE INDEX IF NOT EXISTS idx_escalacoes_criado_em ON abo.escalacoes(criado_em DESC);

-- ============================================
-- TABELA DE MÉTRICAS (agregadas diárias)
-- ============================================
CREATE TABLE IF NOT EXISTS abo.metricas (
  id BIGSERIAL PRIMARY KEY,
  data_metrica DATE DEFAULT CURRENT_DATE,
  total_mensagens INT DEFAULT 0,
  respostas_sucesso INT DEFAULT 0,
  respostas_falha INT DEFAULT 0,
  tempo_resposta_medio FLOAT,
  usuarios_unicos INT DEFAULT 0,
  satisfacao_media FLOAT,
  metadados JSONB,
  criado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_metricas_data ON abo.metricas(data_metrica DESC);

-- ============================================
-- HABILITAR RLS
-- ============================================
ALTER TABLE abo.conversas ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.avaliacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.escalacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.metricas ENABLE ROW LEVEL SECURITY;

-- ============================================
-- FUNÇÃO: atualizar coluna atualizado_em
-- ============================================
CREATE OR REPLACE FUNCTION abo.atualizar_atualizado_em()
RETURNS TRIGGER AS $$
BEGIN
  NEW.atualizado_em = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers para atualizar atualizado_em
DROP TRIGGER IF EXISTS atualizar_conversas_atualizado_em ON abo.conversas;
CREATE TRIGGER atualizar_conversas_atualizado_em
  BEFORE UPDATE ON abo.conversas
  FOR EACH ROW
  EXECUTE FUNCTION abo.atualizar_atualizado_em();

DROP TRIGGER IF EXISTS atualizar_usuarios_atualizado_em ON abo.usuarios;
CREATE TRIGGER atualizar_usuarios_atualizado_em
  BEFORE UPDATE ON abo.usuarios
  FOR EACH ROW
  EXECUTE FUNCTION abo.atualizar_atualizado_em();

DROP TRIGGER IF EXISTS atualizar_avaliacoes_atualizado_em ON abo.avaliacoes;
CREATE TRIGGER atualizar_avaliacoes_atualizado_em
  BEFORE UPDATE ON abo.avaliacoes
  FOR EACH ROW
  EXECUTE FUNCTION abo.atualizar_atualizado_em();

DROP TRIGGER IF EXISTS atualizar_escalacoes_atualizado_em ON abo.escalacoes;
CREATE TRIGGER atualizar_escalacoes_atualizado_em
  BEFORE UPDATE ON abo.escalacoes
  FOR EACH ROW
  EXECUTE FUNCTION abo.atualizar_atualizado_em();

-- ============================================
-- FUNÇÃO: atualizar estatísticas do usuário
-- ============================================
CREATE OR REPLACE FUNCTION abo.atualizar_stats_usuario()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO abo.usuarios (telefone, nome, primeira_interacao, ultima_interacao, total_interacoes)
  VALUES (NEW.telefone, NEW.nome, NOW(), NOW(), 1)
  ON CONFLICT (telefone) DO UPDATE SET
    ultima_interacao = NOW(),
    total_interacoes = abo.usuarios.total_interacoes + 1,
    nome = COALESCE(EXCLUDED.nome, abo.usuarios.nome);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS atualizar_stats_na_conversa ON abo.conversas;
CREATE TRIGGER atualizar_stats_na_conversa
  AFTER INSERT ON abo.conversas
  FOR EACH ROW
  EXECUTE FUNCTION abo.atualizar_stats_usuario();

-- ============================================
-- TABELA DE DOCUMENTOS (RAG - Base de Conhecimento)
-- ============================================
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS abo.documentos (
  id BIGSERIAL PRIMARY KEY,
  titulo VARCHAR(500),
  conteudo TEXT NOT NULL,
  categoria VARCHAR(255),
  metadados JSONB,
  embedding vector(1536),
  fonte VARCHAR(255),
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_documentos_embedding
  ON abo.documentos USING ivfflat (embedding vector_cosine_ops);

CREATE INDEX IF NOT EXISTS idx_documentos_categoria ON abo.documentos(categoria);
CREATE INDEX IF NOT EXISTS idx_documentos_criado_em ON abo.documentos(criado_em DESC);

DROP TRIGGER IF EXISTS atualizar_documentos_atualizado_em ON abo.documentos;
CREATE TRIGGER atualizar_documentos_atualizado_em
  BEFORE UPDATE ON abo.documentos
  FOR EACH ROW
  EXECUTE FUNCTION abo.atualizar_atualizado_em();

-- ============================================
-- FUNÇÃO: buscar documentos similares
-- ============================================
CREATE OR REPLACE FUNCTION abo.buscar_documentos_similares(
  embedding_consulta vector,
  limiar_similaridade FLOAT DEFAULT 0.1,
  limite_resultados INT DEFAULT 3
)
RETURNS TABLE (
  id BIGINT,
  titulo VARCHAR,
  conteudo TEXT,
  categoria VARCHAR,
  metadados JSONB,
  similaridade FLOAT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id,
    d.titulo,
    d.conteudo,
    d.categoria,
    d.metadados,
    (1 - (d.embedding <=> embedding_consulta))::FLOAT as similaridade
  FROM abo.documentos d
  WHERE (1 - (d.embedding <=> embedding_consulta)) > limiar_similaridade
  ORDER BY d.embedding <=> embedding_consulta
  LIMIT limite_resultados;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- VIEWS ANALÍTICAS
-- ============================================
CREATE OR REPLACE VIEW abo.resumo_conversas AS
  SELECT
    DATE(data_hora) as data,
    COUNT(*) as total_conversas,
    COUNT(DISTINCT telefone) as usuarios_unicos,
    AVG(LENGTH(resposta_ia)) as tamanho_medio_resposta,
    MIN(data_hora) as primeira_conversa,
    MAX(data_hora) as ultima_conversa
  FROM abo.conversas
  GROUP BY DATE(data_hora)
  ORDER BY data DESC;

CREATE OR REPLACE VIEW abo.resumo_usuarios AS
  SELECT
    u.telefone,
    u.nome,
    COUNT(c.id) as total_mensagens,
    MAX(c.data_hora) as ultima_interacao,
    MIN(c.data_hora) as primeira_interacao,
    EXTRACT(EPOCH FROM (MAX(c.data_hora) - MIN(c.data_hora))) / NULLIF(COUNT(c.id) - 1, 0) / 3600 as horas_entre_mensagens_media
  FROM abo.usuarios u
  LEFT JOIN abo.conversas c ON u.telefone = c.telefone
  GROUP BY u.id, u.telefone, u.nome
  ORDER BY total_mensagens DESC;

-- ============================================
-- COMENTÁRIOS DE DOCUMENTAÇÃO
-- ============================================
COMMENT ON TABLE abo.conversas IS 'Armazena todas as conversas entre usuários e o assistente ABO-BA';
COMMENT ON TABLE abo.usuarios IS 'Armazena informações de usuários que interagem com o assistente';
COMMENT ON TABLE abo.avaliacoes IS 'Armazena avaliações e comentários dos usuários sobre as respostas';
COMMENT ON TABLE abo.escalacoes IS 'Armazena escalações para atendimento humano';
COMMENT ON TABLE abo.metricas IS 'Armazena métricas agregadas de performance diárias';
COMMENT ON TABLE abo.documentos IS 'Armazena documentos da base de conhecimento com embeddings para RAG';
COMMENT ON FUNCTION abo.buscar_documentos_similares IS 'Busca documentos similares usando vector similarity search';

-- ============================================
-- POLÍTICAS RLS
-- ============================================
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON abo.conversas;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON abo.usuarios;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON abo.avaliacoes;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON abo.escalacoes;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON abo.metricas;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON abo.documentos;
DROP POLICY IF EXISTS "Enable read for authenticated users" ON abo.conversas;
DROP POLICY IF EXISTS "Enable read for authenticated users" ON abo.usuarios;
DROP POLICY IF EXISTS "Enable read for authenticated users" ON abo.avaliacoes;
DROP POLICY IF EXISTS "Enable read for authenticated users" ON abo.escalacoes;
DROP POLICY IF EXISTS "Enable read for authenticated users" ON abo.metricas;
DROP POLICY IF EXISTS "Enable read for authenticated users" ON abo.documentos;

CREATE POLICY "Permitir insercao para usuarios autenticados" ON abo.conversas
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Permitir insercao para usuarios autenticados" ON abo.usuarios
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Permitir insercao para usuarios autenticados" ON abo.avaliacoes
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Permitir insercao para usuarios autenticados" ON abo.escalacoes
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Permitir insercao para usuarios autenticados" ON abo.metricas
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Permitir insercao para usuarios autenticados" ON abo.documentos
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Permitir leitura para usuarios autenticados" ON abo.conversas
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Permitir leitura para usuarios autenticados" ON abo.usuarios
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Permitir leitura para usuarios autenticados" ON abo.avaliacoes
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Permitir leitura para usuarios autenticados" ON abo.escalacoes
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Permitir leitura para usuarios autenticados" ON abo.metricas
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Permitir leitura para usuarios autenticados" ON abo.documentos
  FOR SELECT USING (auth.role() = 'authenticated');




-- ============================================================
-- SUPABASE SETUP V2 - Assistente Completo para Consultório
-- Execute APÓS o SUPABASE_SETUP.sql original
-- ============================================================

-- ============================================
-- 1. TABELA DE DENTISTAS / PROFISSIONAIS
-- ============================================
CREATE TABLE IF NOT EXISTS abo.dentistas (
  id BIGSERIAL PRIMARY KEY,
  nome VARCHAR(255) NOT NULL,
  cro VARCHAR(20) UNIQUE NOT NULL,           -- Registro CRO
  especialidade VARCHAR(255),                 -- Especialidade principal
  especialidades TEXT[],                      -- Múltiplas especialidades
  telefone VARCHAR(20),
  email VARCHAR(255),
  ativo BOOLEAN DEFAULT true,
  dias_trabalho INT[] DEFAULT '{1,2,3,4,5}', -- 0=Dom, 1=Seg...6=Sáb
  inicio_jornada TIME DEFAULT '08:00',
  fim_jornada TIME DEFAULT '18:00',
  inicio_almoco TIME DEFAULT '12:00',
  fim_almoco TIME DEFAULT '13:00',
  duracao_consulta_minutos INT DEFAULT 30,            -- Duração padrão da consulta em minutos
  metadados JSONB DEFAULT '{}',
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dentistas_cro ON abo.dentistas(cro);
CREATE INDEX IF NOT EXISTS idx_dentistas_especialidade ON abo.dentistas(especialidade);
CREATE INDEX IF NOT EXISTS idx_dentistas_ativo ON abo.dentistas(ativo) WHERE ativo = true;

-- ============================================
-- 2. TABELA DE PACIENTES
-- ============================================
CREATE TABLE IF NOT EXISTS abo.pacientes (
  id BIGSERIAL PRIMARY KEY,
  nome VARCHAR(255) NOT NULL,
  cpf VARCHAR(14) UNIQUE,                    -- CPF formatado
  data_nascimento DATE,
  telefone VARCHAR(20) NOT NULL,
  telefone_secundario VARCHAR(20),
  email VARCHAR(255),
  endereco TEXT,
  contato_emergencia_nome VARCHAR(255),
  contato_emergencia_telefone VARCHAR(20),
  alergias TEXT[],                           -- Lista de alergias
  condicoes_medicas TEXT[],                  -- Condições médicas pré-existentes
  medicamentos TEXT[],                       -- Medicamentos em uso
  tipo_sanguineo VARCHAR(5),
  convenio VARCHAR(255),                     -- Convênio/plano
  numero_convenio VARCHAR(50),               -- Número do convênio
  observacoes TEXT,                          -- Observações gerais
  ativo BOOLEAN DEFAULT true,
  cadastrado_via VARCHAR(50) DEFAULT 'whatsapp', -- whatsapp, presencial, website
  usuario_id BIGINT REFERENCES abo.usuarios(id), -- Link com tabela de usuários WhatsApp
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pacientes_cpf ON abo.pacientes(cpf);
CREATE INDEX IF NOT EXISTS idx_pacientes_telefone ON abo.pacientes(telefone);
CREATE INDEX IF NOT EXISTS idx_pacientes_nome ON abo.pacientes(nome);
CREATE INDEX IF NOT EXISTS idx_pacientes_ativo ON abo.pacientes(ativo) WHERE ativo = true;

-- ============================================
-- 3. TABELA DE PROCEDIMENTOS DISPONÍVEIS
-- ============================================
CREATE TABLE IF NOT EXISTS abo.procedimentos (
  id BIGSERIAL PRIMARY KEY,
  codigo VARCHAR(20) UNIQUE,                 -- Código TUSS/interno
  nome VARCHAR(255) NOT NULL,
  descricao TEXT,
  categoria VARCHAR(100),                    -- Ex: preventivo, restaurador, cirúrgico, etc.
  duracao_media_min INT DEFAULT 30,          -- Duração média em minutos
  preco_base DECIMAL(10,2),                  -- Preço base
  requer_anestesia BOOLEAN DEFAULT false,
  instrucoes_pos_op TEXT,                    -- Orientações pós-procedimento
  ativo BOOLEAN DEFAULT true,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_procedimentos_codigo ON abo.procedimentos(codigo);
CREATE INDEX IF NOT EXISTS idx_procedimentos_categoria ON abo.procedimentos(categoria);

-- ============================================
-- 4. TABELA DE AGENDAMENTOS
-- ============================================
CREATE TABLE IF NOT EXISTS abo.agendamentos (
  id BIGSERIAL PRIMARY KEY,
  id_paciente BIGINT REFERENCES abo.pacientes(id),
  id_dentista BIGINT REFERENCES abo.dentistas(id),
  id_procedimento BIGINT REFERENCES abo.procedimentos(id),
  data_consulta DATE NOT NULL,
  hora_consulta TIME NOT NULL,
  hora_fim TIME,
  duracao_min INT DEFAULT 30,
  status VARCHAR(30) DEFAULT 'agendado',     -- agendado, confirmado, em_atendimento, concluido, cancelado, faltou
  motivo_status TEXT,                        -- Motivo de cancelamento/falta
  observacoes TEXT,                          -- Observações do agendamento
  lembrete_enviado BOOLEAN DEFAULT false,
  confirmado_em TIMESTAMPTZ,
  cancelado_em TIMESTAMPTZ,
  agendado_via VARCHAR(50) DEFAULT 'whatsapp', -- whatsapp, presencial, telefone
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agendamentos_paciente ON abo.agendamentos(id_paciente);
CREATE INDEX IF NOT EXISTS idx_agendamentos_dentista ON abo.agendamentos(id_dentista);
CREATE INDEX IF NOT EXISTS idx_agendamentos_data ON abo.agendamentos(data_consulta);
CREATE INDEX IF NOT EXISTS idx_agendamentos_status ON abo.agendamentos(status);
CREATE INDEX IF NOT EXISTS idx_agendamentos_data_dentista ON abo.agendamentos(data_consulta, id_dentista);

-- Constraint: não permitir dois agendamentos no mesmo horário para o mesmo dentista
CREATE UNIQUE INDEX IF NOT EXISTS idx_agendamentos_sem_conflito
  ON abo.agendamentos(id_dentista, data_consulta, hora_consulta)
  WHERE status NOT IN ('cancelado', 'faltou');

-- ============================================
-- 5. TABELA DE PLANOS DE TRATAMENTO
-- ============================================
CREATE TABLE IF NOT EXISTS abo.planos_tratamento (
  id BIGSERIAL PRIMARY KEY,
  id_paciente BIGINT NOT NULL REFERENCES abo.pacientes(id),
  id_dentista BIGINT NOT NULL REFERENCES abo.dentistas(id),
  titulo VARCHAR(255) NOT NULL,              -- Ex: "Tratamento de Canal - Dente 36"
  descricao TEXT,
  status VARCHAR(30) DEFAULT 'proposto',     -- proposto, aprovado, em_andamento, concluido, cancelado
  total_estimado DECIMAL(10,2),             -- Valor total estimado
  total_sessoes INT,                        -- Número total de sessões previstas
  sessoes_concluidas INT DEFAULT 0,
  aprovado_em TIMESTAMPTZ,
  iniciado_em TIMESTAMPTZ,
  concluido_em TIMESTAMPTZ,
  observacoes TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_planos_tratamento_paciente ON abo.planos_tratamento(id_paciente);
CREATE INDEX IF NOT EXISTS idx_planos_tratamento_dentista ON abo.planos_tratamento(id_dentista);
CREATE INDEX IF NOT EXISTS idx_planos_tratamento_status ON abo.planos_tratamento(status);

-- ============================================
-- 6. ITENS DO PLANO DE TRATAMENTO
-- ============================================
CREATE TABLE IF NOT EXISTS abo.itens_tratamento (
  id BIGSERIAL PRIMARY KEY,
  id_plano_tratamento BIGINT NOT NULL REFERENCES abo.planos_tratamento(id) ON DELETE CASCADE,
  id_procedimento BIGINT REFERENCES abo.procedimentos(id),
  numero_dente VARCHAR(10),                  -- Número do dente (notação FDI)
  descricao TEXT,
  status VARCHAR(30) DEFAULT 'pendente',     -- pendente, em_andamento, concluido, cancelado
  preco DECIMAL(10,2),
  id_agendamento BIGINT REFERENCES abo.agendamentos(id), -- Agendamento vinculado
  concluido_em TIMESTAMPTZ,
  observacoes TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_itens_tratamento_plano ON abo.itens_tratamento(id_plano_tratamento);
CREATE INDEX IF NOT EXISTS idx_itens_tratamento_status ON abo.itens_tratamento(status);

-- ============================================
-- 7. TABELA FINANCEIRA
-- ============================================
CREATE TABLE IF NOT EXISTS abo.registros_financeiros (
  id BIGSERIAL PRIMARY KEY,
  id_paciente BIGINT NOT NULL REFERENCES abo.pacientes(id),
  id_plano_tratamento BIGINT REFERENCES abo.planos_tratamento(id),
  id_agendamento BIGINT REFERENCES abo.agendamentos(id),
  tipo VARCHAR(20) NOT NULL,                 -- cobranca, pagamento, desconto, estorno
  valor DECIMAL(10,2) NOT NULL,
  forma_pagamento VARCHAR(50),               -- pix, cartao_credito, cartao_debito, dinheiro, boleto, convenio
  parcelas INT DEFAULT 1,
  descricao TEXT,
  data_vencimento DATE,                      -- Data de vencimento
  pago_em TIMESTAMPTZ,                       -- Data do pagamento
  status VARCHAR(20) DEFAULT 'pendente',     -- pendente, pago, atrasado, cancelado
  numero_recibo VARCHAR(50),
  observacoes TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_registros_financeiros_paciente ON abo.registros_financeiros(id_paciente);
CREATE INDEX IF NOT EXISTS idx_registros_financeiros_status ON abo.registros_financeiros(status);
CREATE INDEX IF NOT EXISTS idx_registros_financeiros_vencimento ON abo.registros_financeiros(data_vencimento);
CREATE INDEX IF NOT EXISTS idx_registros_financeiros_tipo ON abo.registros_financeiros(tipo);

-- ============================================
-- 8. TABELA DE LEMBRETES
-- ============================================
CREATE TABLE IF NOT EXISTS abo.lembretes (
  id BIGSERIAL PRIMARY KEY,
  id_paciente BIGINT NOT NULL REFERENCES abo.pacientes(id),
  id_agendamento BIGINT REFERENCES abo.agendamentos(id),
  tipo VARCHAR(50) NOT NULL,                 -- consulta_24h, consulta_1h, retorno, pagamento, aniversario
  agendado_para TIMESTAMPTZ NOT NULL,        -- Quando enviar o lembrete
  canal VARCHAR(20) DEFAULT 'whatsapp',      -- whatsapp, sms, email
  mensagem TEXT,
  status VARCHAR(20) DEFAULT 'pendente',     -- pendente, enviado, falha
  enviado_em TIMESTAMPTZ,
  tentativas INT DEFAULT 0,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lembretes_agendado ON abo.lembretes(agendado_para) WHERE status = 'pendente';
CREATE INDEX IF NOT EXISTS idx_lembretes_paciente ON abo.lembretes(id_paciente);
CREATE INDEX IF NOT EXISTS idx_lembretes_status ON abo.lembretes(status);

-- ============================================
-- 9. PRONTUÁRIO / REGISTRO CLÍNICO
-- ============================================
CREATE TABLE IF NOT EXISTS abo.prontuarios (
  id BIGSERIAL PRIMARY KEY,
  id_paciente BIGINT NOT NULL REFERENCES abo.pacientes(id),
  id_dentista BIGINT NOT NULL REFERENCES abo.dentistas(id),
  id_agendamento BIGINT REFERENCES abo.agendamentos(id),
  data_registro DATE DEFAULT CURRENT_DATE,
  queixa_principal TEXT,                     -- Queixa principal
  exame_clinico TEXT,                        -- Exame clínico
  diagnostico TEXT,                          -- Diagnóstico
  procedimento_realizado TEXT,               -- Procedimento realizado
  numero_dente VARCHAR(10),                  -- Dente tratado
  materiais_utilizados TEXT,                 -- Materiais utilizados
  prescricoes_texto TEXT,                    -- Prescrições
  observacoes TEXT,                          -- Observações
  proximos_passos TEXT,                      -- Próximos passos
  anexos JSONB DEFAULT '[]',                 -- Links para radiografias, fotos, etc.
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prontuarios_paciente ON abo.prontuarios(id_paciente);
CREATE INDEX IF NOT EXISTS idx_prontuarios_dentista ON abo.prontuarios(id_dentista);
CREATE INDEX IF NOT EXISTS idx_prontuarios_data ON abo.prontuarios(data_registro DESC);

-- ============================================
-- 10. TABELA DE PRESCRIÇÕES
-- ============================================
CREATE TABLE IF NOT EXISTS abo.prescricoes (
  id BIGSERIAL PRIMARY KEY,
  id_paciente BIGINT NOT NULL REFERENCES abo.pacientes(id),
  id_dentista BIGINT NOT NULL REFERENCES abo.dentistas(id),
  id_prontuario BIGINT REFERENCES abo.prontuarios(id),
  data_prescricao DATE DEFAULT CURRENT_DATE,
  medicamentos JSONB NOT NULL,               -- [{nome, dosagem, frequencia, duracao, observacoes}]
  instrucoes TEXT,                           -- Instruções gerais
  valido_ate DATE,
  criado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prescricoes_paciente ON abo.prescricoes(id_paciente);

-- ============================================
-- TRIGGERS para atualizado_em
-- ============================================
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN
    SELECT unnest(ARRAY[
      'dentistas', 'pacientes', 'procedimentos', 'agendamentos',
      'planos_tratamento', 'itens_tratamento', 'registros_financeiros',
      'lembretes', 'prontuarios'
    ])
  LOOP
    EXECUTE format('
      DROP TRIGGER IF EXISTS atualizar_%s_atualizado_em ON abo.%I;
      CREATE TRIGGER atualizar_%s_atualizado_em
        BEFORE UPDATE ON abo.%I
        FOR EACH ROW
        EXECUTE FUNCTION abo.atualizar_atualizado_em();
    ', tbl, tbl, tbl, tbl);
  END LOOP;
END;
$$;

-- ============================================
-- ENABLE RLS
-- ============================================
ALTER TABLE abo.dentistas ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.pacientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.procedimentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.agendamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.planos_tratamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.itens_tratamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.registros_financeiros ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.lembretes ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.prontuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE abo.prescricoes ENABLE ROW LEVEL SECURITY;

-- ============================================
-- FUNÇÕES UTILITÁRIAS
-- ============================================

CREATE EXTENSION IF NOT EXISTS unaccent;

-- Buscar horários disponíveis de um dentista em uma data
CREATE OR REPLACE FUNCTION abo.obter_slots_disponiveis(
  p_id_dentista BIGINT,
  p_data DATE,
  p_duracao_min INT DEFAULT 30
)
RETURNS TABLE (
  slot_inicio TIME,
  slot_fim TIME
) AS $$
DECLARE
  v_inicio_jornada TIME;
  v_fim_jornada TIME;
  v_inicio_almoco TIME;
  v_fim_almoco TIME;
  v_slot_atual TIME;
  v_dias_trabalho INT[];
  v_dia_semana INT;
BEGIN
  -- Buscar configuração do dentista
  SELECT inicio_jornada, fim_jornada, inicio_almoco, fim_almoco, dias_trabalho
  INTO v_inicio_jornada, v_fim_jornada, v_inicio_almoco, v_fim_almoco, v_dias_trabalho
  FROM abo.dentistas
  WHERE id = p_id_dentista AND ativo = true;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Verificar se é dia de trabalho (0=Dom, 1=Seg...6=Sáb)
  v_dia_semana := EXTRACT(DOW FROM p_data)::INT;
  IF NOT (v_dia_semana = ANY(v_dias_trabalho)) THEN
    RETURN;
  END IF;

  -- Gerar slots e verificar disponibilidade
  v_slot_atual := v_inicio_jornada;
  WHILE v_slot_atual + (p_duracao_min || ' minutes')::INTERVAL <= v_fim_jornada LOOP
    -- Pular horário de almoço
    IF v_slot_atual >= v_inicio_almoco AND v_slot_atual < v_fim_almoco THEN
      v_slot_atual := v_fim_almoco;
      CONTINUE;
    END IF;

    -- Verificar se slot não cruza com almoço
    IF v_slot_atual < v_inicio_almoco AND v_slot_atual + (p_duracao_min || ' minutes')::INTERVAL > v_inicio_almoco THEN
      v_slot_atual := v_fim_almoco;
      CONTINUE;
    END IF;

    -- Verificar se não existe agendamento no horário
    IF NOT EXISTS (
      SELECT 1 FROM abo.agendamentos a
      WHERE a.id_dentista = p_id_dentista
        AND a.data_consulta = p_data
        AND a.status NOT IN ('cancelado', 'faltou')
        AND (
          (a.hora_consulta <= v_slot_atual AND a.hora_consulta + (a.duracao_min || ' minutes')::INTERVAL > v_slot_atual)
          OR
          (v_slot_atual <= a.hora_consulta AND v_slot_atual + (p_duracao_min || ' minutes')::INTERVAL > a.hora_consulta)
        )
    ) THEN
      slot_inicio := v_slot_atual;
      slot_fim := v_slot_atual + (p_duracao_min || ' minutes')::INTERVAL;
      RETURN NEXT;
    END IF;

    v_slot_atual := v_slot_atual + (p_duracao_min || ' minutes')::INTERVAL;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Buscar próximos agendamentos de um paciente (por telefone)
CREATE OR REPLACE FUNCTION abo.obter_agendamentos_paciente(
  p_telefone VARCHAR,
  p_status VARCHAR DEFAULT NULL,
  p_limite INT DEFAULT 5
)
RETURNS TABLE (
  id_agendamento BIGINT,
  data_consulta DATE,
  hora_consulta TIME,
  duracao_min INT,
  status VARCHAR,
  nome_dentista VARCHAR,
  especialidade_dentista VARCHAR,
  nome_procedimento VARCHAR,
  observacoes TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    a.id,
    a.data_consulta,
    a.hora_consulta,
    a.duracao_min,
    a.status,
    d.nome,
    d.especialidade,
    pr.nome,
    a.observacoes
  FROM abo.agendamentos a
  JOIN abo.pacientes p ON a.id_paciente = p.id
  JOIN abo.dentistas d ON a.id_dentista = d.id
  LEFT JOIN abo.procedimentos pr ON a.id_procedimento = pr.id
  WHERE p.telefone = p_telefone
    AND (p_status IS NULL OR a.status = p_status)
    AND a.data_consulta >= CURRENT_DATE
  ORDER BY a.data_consulta, a.hora_consulta
  LIMIT p_limite;
END;
$$ LANGUAGE plpgsql;

-- Resumo financeiro do paciente
CREATE OR REPLACE FUNCTION abo.obter_resumo_financeiro_paciente(
  p_telefone VARCHAR
)
RETURNS TABLE (
  total_cobrado DECIMAL,
  total_pago DECIMAL,
  total_pendente DECIMAL,
  total_atrasado DECIMAL,
  proximos_vencimentos JSONB
) AS $$
BEGIN
  RETURN QUERY
  WITH paciente AS (
    SELECT id FROM abo.pacientes WHERE telefone = p_telefone LIMIT 1
  ),
  resumo AS (
    SELECT
      COALESCE(SUM(CASE WHEN f.tipo = 'cobranca' THEN f.valor ELSE 0 END), 0) as cobrado,
      COALESCE(SUM(CASE WHEN f.tipo = 'pagamento' THEN f.valor ELSE 0 END), 0) as pago,
      COALESCE(SUM(CASE WHEN f.tipo = 'cobranca' AND f.status = 'pendente' THEN f.valor ELSE 0 END), 0) as pendente,
      COALESCE(SUM(CASE WHEN f.tipo = 'cobranca' AND f.status = 'atrasado' THEN f.valor ELSE 0 END), 0) as atrasado
    FROM abo.registros_financeiros f
    JOIN paciente p ON f.id_paciente = p.id
  ),
  proximos AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'valor', f.valor,
      'vencimento', f.data_vencimento,
      'descricao', f.descricao
    ) ORDER BY f.data_vencimento), '[]'::jsonb) as itens
    FROM abo.registros_financeiros f
    JOIN paciente p ON f.id_paciente = p.id
    WHERE f.status = 'pendente'
      AND f.tipo = 'cobranca'
      AND f.data_vencimento >= CURRENT_DATE
    LIMIT 5
  )
  SELECT r.cobrado, r.pago, r.pendente, r.atrasado, p.itens
  FROM resumo r, proximos p;
END;
$$ LANGUAGE plpgsql;

-- Buscar paciente por telefone (para o agente)
CREATE OR REPLACE FUNCTION abo.buscar_paciente_por_telefone(p_telefone VARCHAR)
RETURNS TABLE (
  id_paciente BIGINT,
  nome VARCHAR,
  telefone VARCHAR,
  data_nascimento DATE,
  alergias TEXT[],
  condicoes_medicas TEXT[],
  convenio VARCHAR,
  ultima_consulta DATE,
  total_agendamentos BIGINT,
  tratamentos_ativos BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.nome,
    p.telefone,
    p.data_nascimento,
    p.alergias,
    p.condicoes_medicas,
    p.convenio,
    MAX(a.data_consulta),
    COUNT(DISTINCT a.id),
    COUNT(DISTINCT tp.id) FILTER (WHERE tp.status IN ('aprovado', 'em_andamento'))
  FROM abo.pacientes p
  LEFT JOIN abo.agendamentos a ON p.id = a.id_paciente
  LEFT JOIN abo.planos_tratamento tp ON p.id = tp.id_paciente
  WHERE p.telefone = p_telefone AND p.ativo = true
  GROUP BY p.id, p.nome, p.telefone, p.data_nascimento, p.alergias, p.condicoes_medicas, p.convenio;
END;
$$ LANGUAGE plpgsql;

-- Listar dentistas disponíveis (com especialidade opcional)
CREATE OR REPLACE FUNCTION abo.listar_dentistas_disponiveis(
  p_especialidade VARCHAR DEFAULT NULL
)
RETURNS TABLE (
  id_dentista BIGINT,
  nome VARCHAR,
  cro VARCHAR,
  especialidade VARCHAR,
  especialidades TEXT[]
) AS $$
BEGIN
  RETURN QUERY
  SELECT d.id, d.nome, d.cro, d.especialidade, d.especialidades
  FROM abo.dentistas d
  WHERE d.ativo = true
    AND (p_especialidade IS NULL OR d.especialidade ILIKE '%' || p_especialidade || '%'
         OR p_especialidade = ANY(d.especialidades));
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- VIEWS ÚTEIS
-- ============================================

-- Agenda do dia
CREATE OR REPLACE VIEW abo.agenda_hoje AS
SELECT
  a.id as id_agendamento,
  a.hora_consulta,
  a.hora_fim,
  a.duracao_min,
  a.status,
  p.nome as nome_paciente,
  p.telefone as telefone_paciente,
  d.nome as nome_dentista,
  d.especialidade as especialidade_dentista,
  pr.nome as nome_procedimento,
  a.observacoes
FROM abo.agendamentos a
JOIN abo.pacientes p ON a.id_paciente = p.id
JOIN abo.dentistas d ON a.id_dentista = d.id
LEFT JOIN abo.procedimentos pr ON a.id_procedimento = pr.id
WHERE a.data_consulta = CURRENT_DATE
  AND a.status NOT IN ('cancelado', 'faltou')
ORDER BY a.hora_consulta;

-- Pacientes com pagamentos atrasados
CREATE OR REPLACE VIEW abo.pagamentos_atrasados AS
SELECT
  p.nome as nome_paciente,
  p.telefone as telefone_paciente,
  f.valor,
  f.data_vencimento,
  f.descricao,
  (CURRENT_DATE - f.data_vencimento) as dias_atraso
FROM abo.registros_financeiros f
JOIN abo.pacientes p ON f.id_paciente = p.id
WHERE f.tipo = 'cobranca'
  AND f.status IN ('pendente', 'atrasado')
  AND f.data_vencimento < CURRENT_DATE
ORDER BY f.data_vencimento;

-- Lembretes pendentes para enviar
CREATE OR REPLACE VIEW abo.lembretes_pendentes AS
SELECT
  r.id as lembrete_id,
  r.tipo,
  r.agendado_para,
  r.mensagem,
  p.nome as nome_paciente,
  p.telefone as telefone_paciente,
  a.data_consulta,
  a.hora_consulta
FROM abo.lembretes r
JOIN abo.pacientes p ON r.id_paciente = p.id
LEFT JOIN abo.agendamentos a ON r.id_agendamento = a.id
WHERE r.status = 'pendente'
  AND r.agendado_para <= NOW() + INTERVAL '5 minutes'
ORDER BY r.agendado_para;

-- ============================================
-- DADOS INICIAIS - PROCEDIMENTOS COMUNS
-- ============================================
INSERT INTO abo.procedimentos (codigo, nome, descricao, categoria, duracao_media_min, preco_base, requer_anestesia, instrucoes_pos_op) VALUES
  ('PREV001', 'Profilaxia (Limpeza)', 'Limpeza dental profissional com remoção de placa e tártaro', 'preventivo', 30, 150.00, false, 'Evite comer por 30 minutos após o procedimento. Continue escovando normalmente.'),
  ('PREV002', 'Aplicação de Flúor', 'Aplicação tópica de flúor para fortalecimento do esmalte', 'preventivo', 15, 80.00, false, 'Não coma, beba ou enxágue a boca por 30 minutos.'),
  ('PREV003', 'Raspagem Periodontal', 'Raspagem e alisamento radicular para tratamento periodontal', 'preventivo', 60, 250.00, true, 'Pode haver sensibilidade nos próximos dias. Use analgésico se necessário.'),
  ('DIAG001', 'Consulta de Avaliação', 'Consulta inicial com exame clínico completo', 'diagnostico', 30, 120.00, false, NULL),
  ('DIAG002', 'Radiografia Periapical', 'Radiografia periapical digital', 'diagnostico', 15, 50.00, false, NULL),
  ('DIAG003', 'Radiografia Panorâmica', 'Radiografia panorâmica digital', 'diagnostico', 20, 120.00, false, NULL),
  ('REST001', 'Restauração em Resina (1 face)', 'Restauração direta em resina composta - 1 face', 'restaurador', 30, 180.00, true, 'Evite alimentos muito duros nas primeiras 24h. Sensibilidade pode durar alguns dias.'),
  ('REST002', 'Restauração em Resina (2 faces)', 'Restauração direta em resina composta - 2 faces', 'restaurador', 45, 250.00, true, 'Evite alimentos muito duros nas primeiras 24h. Sensibilidade pode durar alguns dias.'),
  ('REST003', 'Restauração em Resina (3+ faces)', 'Restauração direta em resina composta - 3 ou mais faces', 'restaurador', 60, 350.00, true, 'Evite alimentos muito duros nas primeiras 24h. Sensibilidade pode durar alguns dias.'),
  ('ENDO001', 'Tratamento de Canal (1 canal)', 'Endodontia - dente com 1 canal radicular', 'endodontia', 60, 600.00, true, 'Dor leve é normal por 2-3 dias. Use analgésico prescrito. Evite mastigar do lado tratado. Retorne para a restauração definitiva.'),
  ('ENDO002', 'Tratamento de Canal (2 canais)', 'Endodontia - dente com 2 canais radiculares', 'endodontia', 90, 800.00, true, 'Dor leve é normal por 2-3 dias. Use analgésico prescrito. Evite mastigar do lado tratado. Retorne para a restauração definitiva.'),
  ('ENDO003', 'Tratamento de Canal (3+ canais)', 'Endodontia - dente com 3 ou mais canais radiculares', 'endodontia', 120, 1100.00, true, 'Dor leve é normal por 2-3 dias. Use analgésico prescrito. Evite mastigar do lado tratado. Retorne para a restauração definitiva.'),
  ('CIRU001', 'Extração Simples', 'Exodontia simples de dente erupcionado', 'cirurgico', 30, 200.00, true, 'Aplique gelo nas primeiras 24h (20min sim, 20min não). Dieta pastosa por 3 dias. Não cuspa, não use canudo, não fume. Tome medicação prescrita.'),
  ('CIRU002', 'Extração de Siso', 'Exodontia de terceiro molar (siso)', 'cirurgico', 60, 500.00, true, 'Aplique gelo nas primeiras 48h. Dieta líquida/pastosa por 5-7 dias. Repouso por 3 dias. Não cuspa, não use canudo, não fume. Retorne para remoção de pontos em 7 dias.'),
  ('CIRU003', 'Cirurgia Periodontal', 'Procedimento cirúrgico periodontal', 'cirurgico', 90, 800.00, true, 'Siga rigorosamente a medicação prescrita. Dieta pastosa por 7 dias. Evite esforço físico por 5 dias.'),
  ('PROT001', 'Coroa em Porcelana', 'Coroa unitária em porcelana sobre metal ou zircônia', 'protese', 60, 1500.00, true, 'Evite alimentos pegajosos e muito duros. A coroa provisória pode ser sensível. Retorne nas datas agendadas para moldagem e cimentação.'),
  ('PROT002', 'Faceta em Porcelana', 'Faceta laminada em porcelana', 'protese', 60, 2000.00, true, 'Evite morder alimentos muito duros diretamente com os dentes facetados. Mantenha higiene rigorosa.'),
  ('PROT003', 'Prótese Total', 'Prótese total removível (dentadura)', 'protese', 60, 2500.00, false, 'Adaptação leva de 2 a 4 semanas. Retorne para ajustes. Remova para dormir e higienize diariamente.'),
  ('IMPL001', 'Implante Unitário', 'Implante osseointegrado unitário', 'implantodontia', 90, 3500.00, true, 'Dieta pastosa fria por 7 dias. Aplique gelo 48h. Medicação rigorosa. Retorno em 7 dias para revisão. Osseointegração leva 3-6 meses.'),
  ('ORTO001', 'Manutenção Ortodôntica', 'Consulta de manutenção de aparelho ortodôntico', 'ortodontia', 30, 200.00, false, 'Evite alimentos duros e pegajosos. Mantenha higiene rigorosa. Se um braquete soltar, guarde e traga na próxima consulta.'),
  ('ORTO002', 'Instalação de Aparelho Fixo', 'Instalação completa de aparelho ortodôntico fixo', 'ortodontia', 90, 1500.00, false, 'Desconforto é normal por 3-5 dias. Dieta pastosa nos primeiros dias. Cera ortodôntica alivia lesões na mucosa. Higiene reforçada com escova interdental.'),
  ('CLAR001', 'Clareamento em Consultório', 'Clareamento dental profissional em consultório', 'estetica', 90, 1000.00, false, 'Sensibilidade é normal por 24-48h. Dieta branca por 48h (evite café, vinho, beterraba, açaí). Não fume.'),
  ('CLAR002', 'Clareamento Caseiro (kit)', 'Kit de clareamento caseiro supervisionado com moldeira', 'estetica', 30, 600.00, false, 'Use a moldeira conforme orientado (tempo e frequência). Sensibilidade? Pause 1 dia. Dieta branca durante o tratamento.')
ON CONFLICT (codigo) DO NOTHING;

-- ============================================
-- DADOS INICIAIS - DENTISTAS
-- ============================================
INSERT INTO abo.dentistas (nome, cro, especialidade, especialidades, telefone, ativo, dias_trabalho, inicio_jornada, fim_jornada, duracao_consulta_minutos)
VALUES (
  'Andreia Mota Mussi',
  'CRO-4407',                          -- Substitua pelo CRO real
  'Clínico Geral',
  ARRAY['Clínico Geral', 'Prótese Dentária'],
  '7133537900',
  true,
  '{1,2,3,4,5}',                             -- Segunda a Sexta
  '08:00',
  '18:00',
  30
)
ON CONFLICT (cro) DO NOTHING;

-- ============================================
-- FUNÇÃO: Criar agendamento via WhatsApp
-- ============================================
CREATE OR REPLACE FUNCTION abo.criar_agendamento_whatsapp(
  p_telefone_paciente VARCHAR,
  p_nome_paciente VARCHAR,
  p_id_dentista BIGINT,
  p_id_procedimento BIGINT,
  p_data DATE,
  p_horario TIME,
  p_observacoes TEXT DEFAULT NULL
)
RETURNS TABLE (
  sucesso BOOLEAN,
  mensagem TEXT,
  id_agendamento BIGINT
) AS $$
DECLARE
  v_id_paciente BIGINT;
  v_duracao INT;
  v_id_agendamento BIGINT;
BEGIN
  -- Buscar ou criar paciente
  SELECT id INTO v_id_paciente FROM abo.pacientes WHERE telefone = p_telefone_paciente;

  IF v_id_paciente IS NULL THEN
    INSERT INTO abo.pacientes (nome, telefone, cadastrado_via)
    VALUES (p_nome_paciente, p_telefone_paciente, 'whatsapp')
    RETURNING id INTO v_id_paciente;
  END IF;

  -- Buscar duração do procedimento
  SELECT duracao_media_min INTO v_duracao FROM abo.procedimentos WHERE id = p_id_procedimento;
  v_duracao := COALESCE(v_duracao, 30);

  -- Verificar disponibilidade
  IF EXISTS (
    SELECT 1 FROM abo.agendamentos a
    WHERE a.id_dentista = p_id_dentista
      AND a.data_consulta = p_data
      AND a.status NOT IN ('cancelado', 'faltou')
      AND (
        (a.hora_consulta <= p_horario AND a.hora_consulta + (a.duracao_min || ' minutes')::INTERVAL > p_horario)
        OR
        (p_horario <= a.hora_consulta AND p_horario + (v_duracao || ' minutes')::INTERVAL > a.hora_consulta)
      )
  ) THEN
    sucesso := false;
    mensagem := 'Horário indisponível. Por favor, escolha outro horário.';
    id_agendamento := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Criar agendamento
  INSERT INTO abo.agendamentos (id_paciente, id_dentista, id_procedimento, data_consulta, hora_consulta, hora_fim, duracao_min, observacoes, agendado_via)
  VALUES (v_id_paciente, p_id_dentista, p_id_procedimento, p_data, p_horario, p_horario + (v_duracao || ' minutes')::INTERVAL, v_duracao, p_observacoes, 'whatsapp')
  RETURNING id INTO v_id_agendamento;

  -- Criar lembrete 24h antes
  INSERT INTO abo.lembretes (id_paciente, id_agendamento, tipo, agendado_para, mensagem)
  VALUES (
    v_id_paciente, v_id_agendamento, 'consulta_24h',
    (p_data - INTERVAL '1 day') + p_horario,
    format('Olá %s! 😊 Lembramos que você tem consulta amanhã às %s. Confirme sua presença respondendo SIM. Para cancelar ou reagendar, fale conosco!', p_nome_paciente, p_horario::TEXT)
  );

  sucesso := true;
  mensagem := format('Consulta agendada com sucesso para %s às %s!', to_char(p_data, 'DD/MM/YYYY'), p_horario::TEXT);
  id_agendamento := v_id_agendamento;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- FUNÇÃO: Cancelar agendamento
-- ============================================
CREATE OR REPLACE FUNCTION abo.cancelar_agendamento(
  p_id_agendamento BIGINT,
  p_telefone_paciente VARCHAR,
  p_motivo TEXT DEFAULT NULL
)
RETURNS TABLE (sucesso BOOLEAN, mensagem TEXT) AS $$
DECLARE
  v_agend RECORD;
BEGIN
  SELECT a.*, p.telefone INTO v_agend
  FROM abo.agendamentos a
  JOIN abo.pacientes p ON a.id_paciente = p.id
  WHERE a.id = p_id_agendamento AND p.telefone = p_telefone_paciente;

  IF NOT FOUND THEN
    sucesso := false;
    mensagem := 'Agendamento não encontrado.';
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_agend.status IN ('cancelado', 'concluido') THEN
    sucesso := false;
    mensagem := format('Este agendamento já está %s.', v_agend.status);
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE abo.agendamentos
  SET status = 'cancelado', motivo_status = p_motivo, cancelado_em = NOW()
  WHERE id = p_id_agendamento;

  -- Cancelar lembretes pendentes
  UPDATE abo.lembretes SET status = 'cancelado'
  WHERE id_agendamento = p_id_agendamento AND status = 'pendente';

  sucesso := true;
  mensagem := 'Agendamento cancelado com sucesso.';
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- FUNÇÃO: REINICIAR CONVERSA (limpar contexto)
-- ============================================
CREATE OR REPLACE FUNCTION abo.reiniciar_conversa(p_telefone VARCHAR)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_chat_deleted INT;
BEGIN
  -- Limpar histórico de chat do n8n (memória do agente)
  -- Nota: a tabela abo.conversas é preservada para fins de histórico e análise
  DELETE FROM abo.n8n_chat_histories
  WHERE session_id = p_telefone;
  GET DIAGNOSTICS v_chat_deleted = ROW_COUNT;

  RETURN json_build_object(
    'success', true,
    'chat_messages_deleted', v_chat_deleted,
    'message', 'Conversa reiniciada com sucesso. O contexto anterior foi limpo.'
  );
END;
$$;

COMMENT ON FUNCTION abo.reiniciar_conversa IS 'Limpa o histórico de chat e conversas de um telefone para reiniciar o contexto da IA';

-- ============================================
-- COMENTÁRIOS DE DOCUMENTAÇÃO
-- ============================================
COMMENT ON TABLE abo.dentistas IS 'Cadastro de dentistas e profissionais do consultório';
COMMENT ON TABLE abo.pacientes IS 'Cadastro de pacientes com informações médicas e de contato';
COMMENT ON TABLE abo.procedimentos IS 'Catálogo de procedimentos odontológicos disponíveis';
COMMENT ON TABLE abo.agendamentos IS 'Agendamentos de consultas e procedimentos';
COMMENT ON TABLE abo.planos_tratamento IS 'Planos de tratamento propostos e em andamento';
COMMENT ON TABLE abo.itens_tratamento IS 'Itens individuais dentro de um plano de tratamento';
COMMENT ON TABLE abo.registros_financeiros IS 'Registros financeiros: cobranças, pagamentos, etc.';
COMMENT ON TABLE abo.lembretes IS 'Lembretes a serem enviados aos pacientes';
COMMENT ON TABLE abo.prontuarios IS 'Prontuário clínico - registros de atendimento';
COMMENT ON TABLE abo.prescricoes IS 'Prescrições medicamentosas';

COMMENT ON FUNCTION abo.obter_slots_disponiveis IS 'Retorna horários disponíveis de um dentista em uma data';
COMMENT ON FUNCTION abo.obter_agendamentos_paciente IS 'Retorna próximos agendamentos de um paciente por telefone';
COMMENT ON FUNCTION abo.obter_resumo_financeiro_paciente IS 'Resumo financeiro do paciente';
COMMENT ON FUNCTION abo.buscar_paciente_por_telefone IS 'Buscar dados do paciente por telefone';
COMMENT ON FUNCTION abo.criar_agendamento_whatsapp IS 'Criar agendamento via WhatsApp';
COMMENT ON FUNCTION abo.cancelar_agendamento IS 'Cancelar um agendamento existente';

-- ============================================
-- FUNÇÃO: Listar especialidades disponíveis
-- ============================================
CREATE OR REPLACE FUNCTION abo.listar_especialidades_disponiveis()
RETURNS TABLE (
  especialidade VARCHAR,
  dentistas_disponiveis BIGINT,
  nomes_dentistas TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    sub.esp,
    COUNT(DISTINCT sub.dentista_id),
    STRING_AGG(DISTINCT sub.dentista_nome, ', ' ORDER BY sub.dentista_nome)
  FROM (
    SELECT
      UNNEST(
        CASE
          WHEN d.especialidades IS NOT NULL AND array_length(d.especialidades, 1) > 0
          THEN d.especialidades
          ELSE ARRAY[d.especialidade]
        END
      )::VARCHAR AS esp,
      d.id AS dentista_id,
      d.nome AS dentista_nome
    FROM abo.dentistas d
    WHERE d.ativo = true
  ) sub
  GROUP BY sub.esp
  ORDER BY sub.esp;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION abo.listar_especialidades_disponiveis IS 'Lista todas as especialidades disponíveis com quantidade de dentistas';
