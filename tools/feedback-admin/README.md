# Local feedback administrator

This is a local-only admin interface for the remote `klm-feedback-db` D1 database. It is separate from the public `klm-feedback-api` Worker and is not intended to be deployed.

## Start

From this directory:

```bash
cp .dev.vars.example .dev.vars
```

Edit `.dev.vars` and set a long random value for `ADMIN_TOKEN`, then run:

```bash
npx wrangler@latest dev --config wrangler.jsonc
```

Open the local URL shown by Wrangler, normally `http://localhost:8787`.

The UI can list the latest feedback, filter by status, mark entries as `reviewed` or `resolved`, and delete entries after confirmation. All API routes require `Authorization: Bearer <ADMIN_TOKEN>`.

## Safety

The D1 binding uses `remote: true`, so changes made from this local dashboard affect the production database. The admin Worker has no route or `workers.dev` deployment configured. Do not run `wrangler deploy` for this project.
