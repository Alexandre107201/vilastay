# Vila Stay — Gestão de apartamentos Airbnb

Sistema completo de gestão de hospedagem: painel do anfitrião protegido por senha + guia digital do hóspede com link exclusivo por reserva.

**Custo mensal: R$ 0** (GitHub Pages + Supabase gratuitos).

## O que o sistema faz

| Área | Recursos |
|---|---|
| Painel (index.html) | Login com senha · quadro de chegadas/saídas dos próximos 7 dias · alerta quando o hóspede conclui o checkout · reservas com link exclusivo, QR Code e mensagens prontas de WhatsApp · importação automática do calendário do Airbnb (iCal) · múltiplos imóveis · editor do guia (chegada, saída, regras, dicas, FAQ) · modelos de mensagem com variáveis |
| Guia do hóspede (guest.html) | Acesso somente por link com token da reserva (expira 2 dias após o checkout) · cartão da estadia personalizado com nome e datas · passo a passo de chegada com confirmação · Wi-Fi com botão copiar · regras, dicas com mapa e FAQ · botão "Concluí a saída" que avisa o anfitrião · pedido de avaliação no dia do checkout |

## Instalação (uma única vez, ~15 minutos)

### 1. Supabase (banco de dados + login)
1. Crie uma conta gratuita em [supabase.com](https://supabase.com) (pode entrar com GitHub)
2. Crie um projeto (região: South America — São Paulo)
3. Menu **SQL Editor** → cole todo o conteúdo de `setup.sql` → **Run**
4. Menu **Authentication → Users → Add user**: crie seu usuário admin (seu e-mail + uma senha forte). Marque "Auto confirm user".
5. Menu **Settings → API**: copie a **Project URL** e a chave **anon public**

### 2. Configuração
Abra `config.js` e cole a URL e a chave copiadas no passo anterior.
> A chave "anon public" pode ficar pública sem risco: toda a proteção é feita no banco (RLS). Nenhuma tabela é acessível sem login; o hóspede só acessa os dados da própria reserva, via token.

### 3. GitHub Pages (hospedagem)
1. Crie um repositório no GitHub (ex.: `vilastay`) e envie estes 4 arquivos: `index.html`, `guest.html`, `config.js`, `setup.sql` (pelo site: **Add file → Upload files**)
2. **Settings → Pages → Branch: main / (root) → Save**
3. Em ~2 minutos o painel estará em `https://SEU_USUARIO.github.io/vilastay/`

### 4. Primeiro uso
1. Acesse o painel e faça login
2. Aba **Imóvel**: preencha os dados reais (endereço, Wi-Fi, horários, seu WhatsApp, link do Maps, iCal do Airbnb)
3. Aba **Guia**: cadastre os passos de chegada/saída, regras, dicas e FAQ
4. Aba **Reservas**: crie uma reserva de teste com seu próprio nome e abra o link do guia para conferir

## Como pegar o link iCal do Airbnb
Airbnb → **Calendário** do anúncio → **Disponibilidade** → **Conectar a outro site/calendário** → **Copiar link**. Cole na aba Imóvel. Depois use o botão **⟳ Sincronizar Airbnb** na aba Reservas. As reservas chegam como "Hóspede Airbnb" (o Airbnb não expõe o nome no iCal) — edite para colocar nome e WhatsApp.

## Estrutura
```
index.html   → painel do anfitrião (protegido por login)
guest.html   → guia do hóspede (acesso por ?t=TOKEN)
config.js    → suas chaves do Supabase
setup.sql    → cria banco, segurança e funções (rodar 1x no Supabase)
```
