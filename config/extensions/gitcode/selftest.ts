/**
 * Standalone verification for the GitCode wrapper used by the `gitcode` Pi
 * extension. Exercises the same code path the tools use, without Pi or an LLM.
 *
 *   GITCODE_ACCESS_TOKEN=... node selftest.ts
 *
 * Optional: GITCODE_SELFTEST_OWNER / GITCODE_SELFTEST_REPO select the repo.
 */
import { getRepo, listBranches, listPrs, whoami } from "./api.ts";

const owner = process.env.GITCODE_SELFTEST_OWNER ?? "sun_king_poem";
const repo = process.env.GITCODE_SELFTEST_REPO ?? "lu1six";

async function main() {
	const me = await whoami();
	console.log("whoami  :", me.login);

	const r = await getRepo(owner, repo);
	console.log("repo    :", r.full_name, "default:", r.default_branch, "private:", r.private);

	const branches = await listBranches(owner, repo);
	console.log("branches:", branches.map((b) => b.name).join(", ") || "(none)");

	const prs = await listPrs(owner, repo, "all");
	console.log("prs     :", prs.length);

	console.log("SELFTEST_OK");
}

main().catch((err: unknown) => {
	const message = err instanceof Error ? err.message : String(err);
	console.error("SELFTEST_FAIL:", message);
	process.exit(1);
});
