command -v elixir >/dev/null 2>&1 || return 0

# Phoenix Development Aliases and Configuration

# Docker-based development aliases
alias docker.up="docker compose up -d"
alias docker.down="docker compose down"
alias docker.restart="docker compose restart"
alias docker.logs="docker compose logs -f"
alias docker.psql="docker compose exec postgres psql -U postgres"

# Database management (with Docker)
alias db.setup="docker compose up -d && mix ecto.setup"
alias db.reset="mix ecto.reset"
alias db.migrate="mix ecto.migrate"
alias db.rollback="mix ecto.rollback"
alias db.shell="docker compose exec postgres psql -U postgres"

# Phoenix server shortcuts
alias ps="docker compose up -d && mix phx.server"
alias psd="docker compose up -d && iex -S mix phx.server"

# Mix shortcuts
alias mc="mix compile"
alias mcredo="mix credo --strict"
alias mf="mix format"
alias mt="mix test"
alias mtw="mix test.watch"

# IEx helpers
alias iex="iex -S mix"

# Phoenix generators shortcuts
alias mg="mix phx.gen"
alias mgs="mix phx.gen.schema"
alias mgc="mix phx.gen.context"
alias mgh="mix phx.gen.html"
alias mgj="mix phx.gen.json"
alias mgl="mix phx.gen.live"

# Deployment helpers
alias deploy.check="mix format --check-formatted && mix credo --strict && mix test"
alias deploy.assets="mix assets.deploy"
