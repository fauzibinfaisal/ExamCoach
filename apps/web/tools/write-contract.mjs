import { URL } from "node:url";
import { writeFileSync } from "node:fs";
import { linkContractJsonSchema } from "../src/domain/link-contract.ts";
writeFileSync(
  new URL(
    "../../../contracts/web-cbt/link-status.v1.schema.json",
    import.meta.url,
  ),
  JSON.stringify(linkContractJsonSchema, null, 2) + "\n",
);
