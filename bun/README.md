# @xmit-co/bob

Preview server for xmit static sites, written in TypeScript for Bun.

## Features

- Serves static files with smart path resolution (index.html, .html extensions)
- Supports xmit.toml configuration for:
  - Custom headers (with optional path-based matching)
  - Redirects (with regex support)
  - Form handling via email
  - Custom 404 pages
  - Fallback pages (for SPA routing)

## Installation

```bash
bun add @xmit-co/bob
```

## Usage

Add a `bob` configuration to your package.json:

```json
{
  "name": "my-site",
  "scripts": {
    "start": "bun x @xmit-co/bob preview"
  },
  "bob": {
    "directory": "dist"
  }
}
```

Then run:

```bash
bun start
```

Or use the CLI directly:

```bash
bunx @xmit-co/bob preview

# With custom listen address
bunx @xmit-co/bob preview --listen :8080
bunx @xmit-co/bob preview --listen localhost:3000
```

## Configuration

### package.json

```json
{
  "bob": {
    "directory": "dist",
    "sites": {
      "prod": {
        "domain": "example.com",
        "service": "xmit.co"
      }
    }
  }
}
```

### xmit.toml

Place an `xmit.toml` file in your site directory to configure server behavior:

```toml
fallback = "index.html"  # For SPA routing
"404" = "404.html"       # Custom 404 page

[[headers]]
name = "Cache-Control"
value = "public, max-age=3600"
on = "\\.(js|css|png|jpg)$"  # Optional regex pattern

[[redirects]]
from = "^/old-path$"
to = "/new-path"
permanent = true

[[forms]]
from = "/contact"
to = "you@example.com"
then = "/thanks"  # Optional redirect after submission
```

## CLI Options

- `--listen ADDRESS`: Override the default listen address (default: `localhost:4000`)
  - `--listen :4000` - Listen on all interfaces, port 4000
  - `--listen localhost:3000` - Listen on localhost, port 3000
  - `--listen 8080` - Listen on localhost, port 8080

## API

You can also use the server programmatically:

```typescript
import { serve, createServer } from "@xmit-co/bob";

// Simple usage
await serve("/path/to/site", ":4000");

// Advanced usage
const server = await createServer({
  directory: "/path/to/site",
  port: 4000,
  hostname: "localhost"
});
```

## License

MIT
