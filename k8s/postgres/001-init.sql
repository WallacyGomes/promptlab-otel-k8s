CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR(80) NOT NULL UNIQUE,
  slug VARCHAR(80) NOT NULL UNIQUE,
  description TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS prompts (
  id SERIAL PRIMARY KEY,
  category_id INTEGER NOT NULL REFERENCES categories(id),
  title VARCHAR(140) NOT NULL,
  description TEXT NOT NULL,
  prompt_text TEXT NOT NULL,
  price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
  tags TEXT[] NOT NULL DEFAULT '{}',
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY,
  buyer_name VARCHAR(120) NOT NULL,
  buyer_email VARCHAR(160) NOT NULL,
  total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
  status VARCHAR(40) NOT NULL DEFAULT 'paid_simulated',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
  id SERIAL PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  prompt_id INTEGER NOT NULL REFERENCES prompts(id),
  quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0)
);

CREATE TABLE IF NOT EXISTS prompt_events (
  id BIGSERIAL PRIMARY KEY,
  prompt_id INTEGER NOT NULL REFERENCES prompts(id),
  event_type VARCHAR(40) NOT NULL,
  source VARCHAR(80) NOT NULL DEFAULT 'store-node',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prompts_category_active ON prompts(category_id, active);
CREATE INDEX IF NOT EXISTS idx_prompt_events_prompt_type ON prompt_events(prompt_id, event_type);
CREATE INDEX IF NOT EXISTS idx_order_items_prompt ON order_items(prompt_id);

INSERT INTO categories (name, slug, description) VALUES
  ('Marketing', 'marketing', 'Prompts para campanhas, copywriting, funis e posicionamento.'),
  ('Desenvolvimento', 'desenvolvimento', 'Prompts para arquitetura, revisao de codigo, testes e documentacao tecnica.'),
  ('Imagem', 'imagem', 'Prompts para gerar imagens, direcao visual, estilos e composicao.'),
  ('Produtividade', 'produtividade', 'Prompts para planejamento, analise, rotina e organizacao.')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO prompts (category_id, title, description, prompt_text, price_cents, tags)
SELECT c.id, p.title, p.description, p.prompt_text, p.price_cents, p.tags
FROM (
  VALUES
    ('marketing', 'Landing page que converte', 'Brief completo para criar uma landing page com proposta clara, provas e CTA.', 'Atue como estrategista de conversao. Crie uma landing page para [produto] focada em [persona], com headline, subheadline, secoes, provas, objeÃ§Ãµes e CTA.', 2900, ARRAY['copy', 'landing-page', 'conversao']),
    ('marketing', 'Sequencia de emails para lancamento', 'Gera uma sequencia de emails para pre-lancamento, abertura e fechamento.', 'Crie uma sequencia de 7 emails para lancar [oferta], considerando dores, beneficios, prova social, urgencia legitima e follow-up.', 3900, ARRAY['email', 'lancamento', 'funil']),
    ('marketing', 'Anuncio Meta Ads com variacoes', 'Cria angulos, headlines e textos curtos para testes A/B.', 'Gere 10 variacoes de anuncios para Meta Ads sobre [produto], separando angulo, headline, texto principal, CTA e hipotese de teste.', 2500, ARRAY['ads', 'ab-test', 'performance']),
    ('desenvolvimento', 'Revisor senior de pull request', 'Prompt para revisar PR com foco em bugs, seguranca, testes e manutencao.', 'Atue como engenheiro senior. Revise este diff procurando bugs, regressÃµes, riscos de seguranca, problemas de concorrencia e testes faltantes: [diff].', 3200, ARRAY['code-review', 'qualidade', 'testes']),
    ('desenvolvimento', 'Gerador de testes unitarios', 'Transforma um trecho de codigo em uma suite de testes objetiva.', 'Crie testes unitarios para o codigo abaixo. Cubra caminhos felizes, erros, bordas e mocks necessarios. Explique apenas os cenarios: [codigo].', 2800, ARRAY['tests', 'unit', 'dev']),
    ('desenvolvimento', 'Arquitetura de microservico', 'Ajuda a desenhar contrato, persistencia, filas e observabilidade.', 'Desenhe uma arquitetura de microservico para [dominio], incluindo endpoints, modelo de dados, eventos, falhas, observabilidade e testes.', 4500, ARRAY['arquitetura', 'microservicos', 'api']),
    ('imagem', 'Retrato editorial premium', 'Prompt visual com direcao de luz, lente, composicao e acabamento.', 'Crie um prompt de imagem para um retrato editorial de [pessoa/persona], com lente, iluminacao, figurino, fundo, enquadramento e estilo final.', 2200, ARRAY['retrato', 'fotografia', 'editorial']),
    ('imagem', 'Mockup de produto digital', 'Gera prompt para imagem de produto SaaS em contexto realista.', 'Crie um prompt para mockup de [produto digital], mostrando tela principal, contexto de uso, materiais, iluminacao e detalhes de interface.', 2600, ARRAY['mockup', 'produto', 'saas']),
    ('imagem', 'Guia de estilo visual para marca', 'Prompt para explorar paleta, tipografia, formas e atmosfera.', 'Atue como diretor de arte. Gere uma direcao visual para [marca], com paleta, tipografia, fotografia, layout, textura e exemplos de aplicacao.', 3400, ARRAY['branding', 'direcao-visual', 'marca']),
    ('produtividade', 'Planejamento semanal executivo', 'Organiza objetivos, prioridades, agenda e riscos da semana.', 'Monte um plano semanal para [contexto], com objetivos, prioridades, blocos de foco, riscos, dependencias e criterio de sucesso.', 1900, ARRAY['planejamento', 'rotina', 'gestao']),
    ('produtividade', 'Resumo decisorio de reuniao', 'Transforma notas brutas em decisoes, pendencias e proximos passos.', 'A partir destas notas de reuniao, extraia decisoes, acoes, responsaveis, prazos, riscos e perguntas abertas: [notas].', 2100, ARRAY['reuniao', 'resumo', 'acoes']),
    ('produtividade', 'Analista de tradeoffs', 'Ajuda a comparar alternativas com criterios objetivos.', 'Compare as alternativas [A, B, C] para [decisao]. Use criterios, pesos, riscos, custo de reversao e recomendacao final.', 2400, ARRAY['decisao', 'analise', 'tradeoffs'])
) AS p(slug, title, description, prompt_text, price_cents, tags)
JOIN categories c ON c.slug = p.slug
ON CONFLICT DO NOTHING;

INSERT INTO prompt_events (prompt_id, event_type, source)
SELECT id, 'view', 'seed' FROM prompts WHERE id IN (1, 2, 4, 4, 6, 9, 10);

INSERT INTO prompt_events (prompt_id, event_type, source)
SELECT id, 'purchase', 'seed' FROM prompts WHERE id IN (1, 4, 6, 10);
