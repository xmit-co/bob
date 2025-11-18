import { file, type Server } from "bun";
import { parse as parseToml } from "@iarna/toml";
import { join, resolve } from "path";
import { existsSync, statSync } from "fs";
import type { XmitConfig } from "./config";
import { v4 as uuidv4 } from "./uuid";

interface ServeOptions {
  directory: string;
  port?: number;
  hostname?: string;
}

function openFile(path: string): string | null {
  try {
    const stat = statSync(path);
    if (!stat.isDirectory()) {
      return path;
    }
  } catch {
    // File doesn't exist or can't be accessed
  }
  return null;
}

async function sendFormByMail(request: Request, to: string): Promise<void> {
  const contentType = request.headers.get("Content-Type") || "";
  const formData = await request.formData();

  let replyTo = formData.get("email")?.toString() || "";
  let from: string;

  // Simple email validation
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(replyTo)) {
    replyTo = "noreply@forms.xmit.co";
    from = "noreply@forms.xmit.co";
  } else {
    from = replyTo.replace("@", ".") + "@forms.xmit.co";
  }

  const fromName = formData.get("name")?.toString() || new URL(request.url).hostname;
  let subject = formData.get("subject")?.toString() || "Form submission";
  subject = `[${new URL(request.url).hostname}] ${subject}`;

  const header: Record<string, any> = {};
  const specialFields = new Set(["email", "name", "subject", "message"]);

  for (const [key, value] of formData.entries()) {
    if (specialFields.has(key) || value instanceof File) {
      continue;
    }

    const existing = header[key];
    if (existing === undefined) {
      header[key] = value;
    } else if (Array.isArray(existing)) {
      existing.push(value);
    } else {
      header[key] = [existing, value];
    }
  }

  let body = "";
  if (Object.keys(header).length > 0) {
    // Simple TOML-like encoding
    body += "---\n";
    for (const [key, value] of Object.entries(header)) {
      if (Array.isArray(value)) {
        body += `${key} = ${JSON.stringify(value)}\n`;
      } else {
        body += `${key} = ${JSON.stringify(value)}\n`;
      }
    }
    body += "---\n";
  }
  body += formData.get("message")?.toString() || "";

  console.log(`From: ${fromName} <${from}>`);
  console.log(`Reply-To: ${fromName} <${replyTo}>`);
  console.log(`To: ${to}`);
  console.log(`Subject: ${subject}`);

  // Log attachments
  for (const [key, value] of formData.entries()) {
    if (value instanceof File) {
      const content = await value.arrayBuffer();
      console.log(`Attachment: ${key}_${value.name} (${content.byteLength} bytes)`);
    }
  }

  console.log(body);
}

function internalError(error: Error): Response {
  const id = uuidv4();
  console.error(`${id}: ${error.message}`);
  return new Response(`Internal error (${id})`, { status: 500 });
}

export async function createServer(options: ServeOptions): Promise<Server> {
  const { directory, port = 4000, hostname = "localhost" } = options;
  const absDirectory = resolve(directory);

  return Bun.serve({
    port,
    hostname,
    async fetch(request: Request): Promise<Response> {
      // Load xmit.toml configuration
      let config: XmitConfig = {};
      const cfgPath = join(absDirectory, "xmit.toml");

      try {
        const cfgFile = file(cfgPath);
        if (await cfgFile.exists()) {
          const cfgText = await cfgFile.text();
          config = parseToml(cfgText) as XmitConfig;
        }
      } catch (err) {
        if (existsSync(cfgPath)) {
          console.warn(`⚠️ ${cfgPath}: ${err}`);
        }
      }

      const url = new URL(request.url);
      const headers = new Headers();

      // Set default security headers
      headers.set("Server", "xmit");
      headers.set("X-Frame-Options", "SAMEORIGIN");
      headers.set("X-Content-Type-Options", "nosniff");
      headers.set("Referrer-Policy", "no-referrer");
      headers.set("Accept-Ranges", "bytes");

      // Apply custom headers from config
      if (config.headers) {
        for (const header of config.headers) {
          let apply = false;

          if (!header.on) {
            apply = true;
          } else {
            try {
              const re = new RegExp(header.on);
              apply = re.test(url.pathname);
            } catch {
              continue;
            }
          }

          if (apply) {
            if (header.value === null || header.value === undefined) {
              headers.delete(header.name);
            } else {
              headers.set(header.name, header.value);
            }
          }
        }
      }

      // Handle POST requests (forms)
      if (request.method === "POST") {
        let matched = false;

        if (config.forms) {
          for (const form of config.forms) {
            if (form.from === url.pathname) {
              matched = true;
              try {
                await sendFormByMail(request, form.to);

                if (form.then) {
                  return Response.redirect(
                    new URL(form.then, request.url).toString(),
                    302
                  );
                }

                return new Response("OK", { headers });
              } catch (err) {
                return internalError(err as Error);
              }
            }
          }
        }

        if (!matched) {
          return new Response("Method not allowed", {
            status: 405,
            headers
          });
        }
      }

      // File serving logic
      let status = 200;
      const path = url.pathname.slice(1); // Remove leading /
      const originalPath = join(absDirectory, path);
      let realPath = originalPath;
      let foundFile = openFile(realPath);

      // Try index.html in directory
      if (!foundFile) {
        realPath = join(originalPath, "index.html");
        foundFile = openFile(realPath);
      }

      // Try .html extension
      if (!foundFile) {
        realPath = originalPath + ".html";
        foundFile = openFile(realPath);
      }

      // Try redirects
      if (!foundFile && config.redirects) {
        for (const redirect of config.redirects) {
          try {
            const from = new RegExp(redirect.from);
            if (from.test(url.pathname)) {
              const to = url.pathname.replace(from, redirect.to);
              const code = redirect.permanent ? 301 : 307;
              return Response.redirect(new URL(to, request.url).toString(), code);
            }
          } catch {
            continue;
          }
        }
      }

      // Try fallback
      if (!foundFile && config.fallback) {
        realPath = join(absDirectory, config.fallback);
        foundFile = openFile(realPath);
      }

      // Try 404 page
      if (!foundFile) {
        status = 404;
        if (config["404"]) {
          realPath = join(absDirectory, config["404"]);
          foundFile = openFile(realPath);
        }
      }

      // Return 404 if still no file found
      if (!foundFile) {
        return new Response("Not Found", {
          status: 404,
          headers
        });
      }

      // Serve the file
      const f = file(foundFile);

      // Set status if not OK
      if (status !== 200) {
        headers.set("Status", status.toString());
      }

      return new Response(f, {
        status,
        headers
      });
    },
  });
}

export async function serve(directory: string, listen?: string): Promise<void> {
  const listenAddr = listen || process.env.LISTEN || ":4000";

  let hostname = "localhost";
  let port = 4000;

  if (listenAddr.startsWith(":")) {
    port = parseInt(listenAddr.slice(1), 10);
  } else if (listenAddr.includes(":")) {
    const parts = listenAddr.split(":");
    hostname = parts[0];
    port = parseInt(parts[1], 10);
  } else {
    port = parseInt(listenAddr, 10);
  }

  const server = await createServer({ directory, port, hostname });

  const serveAddr = hostname === "0.0.0.0" ? "localhost" : hostname;

  if (!listen) {
    console.log(`Listening on ${hostname}:${port} (pass --listen to override)`);
  } else {
    console.log(`Listening on ${hostname}:${port}`);
  }

  console.log(`Preview of ${directory}: http://${serveAddr}:${port}`);
}
