# Example Usage

## Basic Setup

1. Create a project with a `package.json`:

```json
{
  "name": "my-site",
  "version": "1.0.0",
  "scripts": {
    "start": "bob preview"
  },
  "bob": {
    "directory": "dist"
  },
  "devDependencies": {
    "@xmit-co/bob": "^0.1.0"
  }
}
```

2. Create your site in the `dist` directory:

```bash
mkdir -p dist
echo '<h1>Hello World</h1>' > dist/index.html
```

3. Install and run:

```bash
bun install
bun start
```

## Advanced Configuration

### xmit.toml

Create `dist/xmit.toml` to configure server behavior:

```toml
# Custom 404 page
"404" = "404.html"

# Fallback for SPA routing (serve index.html for non-existent paths)
fallback = "index.html"

# Add custom headers
[[headers]]
name = "Cache-Control"
value = "public, max-age=3600"
on = "\\.(js|css|png|jpg|svg)$"  # Only for static assets

[[headers]]
name = "X-Custom-Header"
value = "my-value"  # Applied to all requests

# Remove a default header
[[headers]]
name = "X-Frame-Options"
# No value means delete the header

# Redirects with regex support
[[redirects]]
from = "^/blog/(.+)$"
to = "/posts/$1"
permanent = true  # 301 redirect (default is 307)

[[redirects]]
from = "^/old-page$"
to = "/new-page"

# Form handling
[[forms]]
from = "/contact"
to = "your-email@example.com"
then = "/thanks"  # Optional redirect after submission
```

## File Serving Behavior

The server tries to serve files in this order:

1. Exact path: `/foo` → `dist/foo`
2. Directory index: `/foo` → `dist/foo/index.html`
3. HTML extension: `/foo` → `dist/foo.html`
4. Redirects (if configured in xmit.toml)
5. Fallback (if configured in xmit.toml)
6. 404 page (if configured in xmit.toml)
7. Default 404 response

## Form Handling Example

HTML form:

```html
<form action="/contact" method="POST">
  <input type="text" name="name" required>
  <input type="email" name="email" required>
  <input type="text" name="subject" placeholder="Optional">
  <textarea name="message" required></textarea>
  <button type="submit">Send</button>
</form>
```

The form submission will:
1. Parse the form data
2. Log the email details to the console (in preview mode)
3. Redirect to the `then` URL if specified
4. Return 200 OK if no redirect is configured

## CLI Options

```bash
# Listen on all interfaces
bob preview --listen :8080

# Listen on specific host and port
bob preview --listen 0.0.0.0:3000

# Just port (defaults to localhost)
bob preview --listen 5000
```

## Programmatic Usage

```typescript
import { serve, createServer } from "@xmit-co/bob";

// Simple usage
await serve("/path/to/site", ":4000");

// Get server instance for more control
const server = await createServer({
  directory: "/path/to/site",
  port: 4000,
  hostname: "localhost"
});

console.log(`Server running on ${server.hostname}:${server.port}`);

// Stop the server later
server.stop();
```
