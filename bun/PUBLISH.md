# Publishing to npm

## Prerequisites

1. You need npm installed (comes with Node.js)
2. You need to be logged in to npm: `npm login`
3. You need publish access to the @xmit-co organization

## Publishing Steps

1. **Update the version** in `package.json`:
   ```bash
   # For patch releases (bug fixes)
   npm version patch

   # For minor releases (new features)
   npm version minor

   # For major releases (breaking changes)
   npm version major
   ```

2. **Build the package**:
   ```bash
   bun run build
   ```

3. **Test the package locally** (optional):
   ```bash
   npm pack
   # This creates a .tgz file you can inspect
   ```

4. **Publish to npm**:
   ```bash
   npm publish
   ```

   The `prepublishOnly` script will automatically run `bun run build` before publishing.

## First-time Setup

If this is the first time publishing:

1. Create an npm account at https://www.npmjs.com/signup
2. Login via CLI: `npm login`
3. Create the @xmit-co organization (or get added to it)
4. Publish: `npm publish`

## Verification

After publishing, verify at:
- https://www.npmjs.com/package/@xmit-co/bob

Test installation:
```bash
bunx @xmit-co/bob@latest
```

## Troubleshooting

- **403 Forbidden**: You don't have publish rights to @xmit-co
- **Version exists**: You need to bump the version number
- **Build failed**: Run `bun run build` manually to see errors
