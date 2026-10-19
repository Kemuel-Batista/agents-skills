# Agents & Skills

Repositorio pessoal para manter skills de agentes sincronizadas entre maquinas.
As skills ficam no Git; os clientes recebem apenas symlinks para elas. Por isso,
uma alteracao ou `git pull` passa a valer sem copiar os arquivos novamente.

## Por que nao linkar `~/.codex` e `~/.claude` inteiros

Esses diretorios tambem guardam configuracoes, cache, historico, sessoes e dados
especificos de cada maquina. Este projeto cria links somente para cada skill:

- `~/.agents/skills`: local pessoal recomendado pelo Codex;
- `~/.claude/skills`: local pessoal do Claude Code;
- `~/.codex/skills`: local legado opcional, habilitado com `--legacy-codex`.

Codex e Claude Code suportam skills cujo diretorio e um symlink. Consulte as
documentacoes oficiais de [skills no Codex](https://developers.openai.com/codex/skills)
e [skills no Claude Code](https://code.claude.com/docs/en/skills).

## Estrutura

```text
agents-skills/
├── skills/                    # suas skills, versionadas
├── external/                  # clones de terceiros, ignorados pelo Git
│   └── repos.tsv              # fontes externas reproduziveis
└── scripts/
    ├── install.sh             # instala todas as skills proprias
    ├── install-external.sh    # seleciona skills de terceiros
    └── update-external.sh     # clona/atualiza fontes externas
```

## Primeira instalacao

Depois de clonar este repositorio:

```bash
./scripts/update-external.sh
./scripts/install.sh
./scripts/install-external.sh
```

O ultimo comando abre uma selecao interativa. Para automacao, informe as skills
explicitamente:

```bash
./scripts/install-external.sh --list
./scripts/install-external.sh code-review tdd
./scripts/install-external.sh --installed
./scripts/install-external.sh --remove tdd
```

Por padrao, um arquivo ou link existente nunca e sobrescrito. Para substituir um
conflito de forma recuperavel, use `--replace`; o item anterior sera movido para
`~/.agent-skills-backups/<data>/`.

## Uso diario

Para as skills proprias, basta atualizar o repositorio:

```bash
git pull --ff-only
```

Os symlinks continuam apontando para os mesmos diretorios e enxergam o conteudo
novo imediatamente. Execute `install.sh` novamente apenas quando adicionar uma
nova pasta de skill.

As fontes de terceiros possuem historico Git independente. Atualize-as com:

```bash
./scripts/update-external.sh
```

Somente as externas escolhidas anteriormente ficam expostas aos clientes; atualizar
um clone nao instala todas as suas skills.

## Adicionar conteudo

Uma skill propria deve ter esta forma:

```text
skills/minha-skill/
└── SKILL.md
```

Para adicionar um repositorio externo, inclua uma linha tabulada em
`external/repos.tsv`:

```text
nome-do-diretorio<TAB>https://github.com/owner/repo.git
```

Depois rode `update-external.sh` e escolha as skills desejadas com
`install-external.sh`.

### Skills de Instagram

O [instagram-agent-skill](https://github.com/Jakeschincariol/instagram-agent-skill)
esta registrado em `external/repos.tsv`. Para listar ou instalar as 13 skills:

```bash
./scripts/update-external.sh
./scripts/install-external.sh --list --repo instagram-agent-skill
./scripts/install-external.sh --all --repo instagram-agent-skill
```

Para instalar apenas algumas, use os nomes, por exemplo:

```bash
./scripts/install-external.sh ig-reel ig-caption ig-human
```

No Codex, invoque com `$ig-reel`, `$ig-caption` ou outra skill instalada.
Os scripts auxiliares exigem Python 3. O clone preserva os arquivos originais
para continuar recebendo atualizacoes; as skills usam `~/.claude/instagram/`
para voz, historico e planejamento, inclusive quando executadas pelo Codex.

Prepare o perfil de voz sem sobrescrever um arquivo existente e preencha-o
com seu publico, tom de voz e exemplos:

```bash
mkdir -p ~/.claude/instagram
cp -n external/instagram-agent-skill/templates/voice.md ~/.claude/instagram/voice.md
```

### Viral Instagram Reels

O [content-skills da Vyral](https://github.com/vyralcontent/content-skills) esta
registrado em `external/repos.tsv`. Para instalar somente a skill de Reels no
Codex e no Claude Code, inclusive em outra maquina apos clonar este projeto:

```bash
./scripts/update-external.sh
./scripts/install-external.sh vyralcontent-skills:viral-instagram-reels
```

No Codex, invoque com `$viral-instagram-reels` para criar roteiros, melhorar
ganchos ou analisar o desempenho de Reels. O clone preserva as referencias e
os modelos originais; `update-external.sh` atualiza o conteudo pelos links.

### Skills da CreatorSkills

Estas skills ficam versionadas em `skills/`, com as instrucoes principais
disponibilizadas nas paginas originais e metadados para descoberta no Codex e
no Claude Code:

- [Instagram Reels Script Writer](https://creatorskills.co/skills/instagram-reels-script-writer):
  `$instagram-reels-script-writer` gera roteiros com falas, cenas e texto na tela.
- [Content Repurposing Planner](https://creatorskills.co/skills/content-repurposing-planner):
  `$content-repurposing-planner` planeja como transformar aulas, lives e videos
  longos em Reels e outros conteudos; nao edita os videos.
- [Newsletter Subscriber Growth Engine](https://creatorskills.co/skills/newsletter-subscriber-growth-engine):
  `$newsletter-subscriber-growth-engine` ajuda a planejar captacao de emails,
  materiais gratuitos e mensagens de boas-vindas para interessados no curso.
- [Content Idea Brainstormer](https://creatorskills.co/skills/content-idea-brainstormer):
  `$content-idea-brainstormer` gera ideias especificas de conteudo para seu nicho.
- [Creator Bio Generator](https://creatorskills.co/skills/creator-bio-generator):
  `$creator-bio-generator` escreve bios adaptadas ao publico e a plataforma.
- [Email Subject Line Optimizer](https://creatorskills.co/skills/email-subject-line-optimizer):
  `$email-subject-line-optimizer` cria opcoes de assunto para emails e lancamentos.
- [Creator Productivity Second Brain](https://creatorskills.co/skills/creator-productivity-second-brain):
  `$creator-productivity-second-brain` organiza metas, ideias e rotina de producao.

Os corpos das instrucoes foram preservados; os cabecalhos foram adicionados ou
ajustados para identificar as skills e registrar a fonte. Os arquivos auxiliares
`README.md` e `EXAMPLE.md` anunciados nos pacotes nao estao incluidos.

Para instalar nesta ou em outra maquina apos clonar o projeto:

```bash
./scripts/install.sh
```

Estas copias recebem atualizacoes pelo Git deste projeto; atualizacoes das
fontes precisam ser incorporadas manualmente.

### Skills de Go

O [cc-skills-golang](https://github.com/samber/cc-skills-golang) esta registrado
em `external/repos.tsv`. Para baixar e instalar o conjunto completo no Codex
e no Claude Code:

```bash
./scripts/update-external.sh
./scripts/install-external.sh --all --repo cc-skills-golang
```

Para consultar as skills disponiveis ou instalar apenas algumas:

```bash
./scripts/install-external.sh --list --repo cc-skills-golang
./scripts/install-external.sh --repo cc-skills-golang golang-testing golang-concurrency
```

O autor recomenda instalar o conjunto completo, pois as skills referenciam umas
as outras. Para atualizar o conteudo, execute `./scripts/update-external.sh`;
os links existentes passam a usar a versao atualizada.

### Content Principles

O [content-principles](https://github.com/aiwithremy/content-principles) esta
registrado em `external/repos.tsv`. Para instalar a skill no Codex e no Claude
Code:

```bash
./scripts/update-external.sh
./scripts/install-external.sh --all --repo content-principles
```

No Codex, invoque com `$content-principles` para criar ou revisar roteiros de
videos curtos, ganchos e posts com foco em atencao e curiosidade.

## Criar e publicar este repositorio

Se a pasta ainda nao for um repositorio Git, inicialize-a e conecte-a ao seu remoto:

```bash
git init -b main
git add .
git commit -m "chore: bootstrap agent skills"
git remote add origin git@github.com:SEU-USUARIO/agents-skills.git
git push -u origin main
```

Nao versione credenciais nem copie `config.toml`, `settings.json`, historicos ou
arquivos de autenticacao para este repositorio.

