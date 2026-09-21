# Web CBT public contracts

`link-status.v1.schema.json` describes the public landing response only.
It is generated from the strict Zod schema in
`apps/web/src/domain/link-contract.ts`; a unit test requires exact equality.
Unknown fields are rejected, including credentials, owner IDs and question data.

- `ready`: server-issued timestamps and bounded tryout presentation metadata.
- `claimed`: already bound elsewhere/ownership not established; no metadata.
- `expired`, `revoked`, `completed`, `invalid`: redacted status only.
- `validating`: client loading state, never a server response.

Additional semantic checks: createdAt <= serverNow; expiresAt = createdAt + 12h;
serverNow >= expiresAt becomes expired; remaining duration below exam+grace
fails closed. The client checks are defensive presentation checks, not server
expiry enforcement. No browser Date or clock determines authorization.

The schema deliberately contains no create/claim/answer/submit implementation.
The Node gateway must validate its own outputs and authorization in W2/W3;
sharing a response schema does not make a web client trusted. Future request
contracts and Dart consumers require explicit versioning and parity tests.
