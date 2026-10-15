/**
 * `gitcode` Pi extension — native tools for operating GitCode.
 *
 * These tools cover the GitCode *API* half of a task (identity, repositories,
 * forks, pull requests). The SCM half (clone, branch, commit, push) stays with
 * the built-in bash tool and git.
 *
 * Auth: `GITCODE_ACCESS_TOKEN`. See the `gitcode-api` skill for the full API.
 */
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
	GitCodeError,
	createPr,
	forkRepo,
	getPr,
	getRepo,
	listBranches,
	listPrs,
	whoami,
} from "./api.ts";

const text = (t: string) => [{ type: "text" as const, text: t }];

const whoamiTool = defineTool({
	name: "gitcode_whoami",
	label: "GitCode: identity",
	description:
		"Return the authenticated GitCode user (login, name, profile URL). Use it to confirm GitCode credentials before acting.",
	parameters: Type.Object({}),
	async execute() {
		const me = await whoami();
		return {
			content: text(`GitCode user: ${me.login}${me.name ? ` (${me.name})` : ""}\nprofile: ${me.html_url ?? ""}`),
			details: { login: me.login, name: me.name, html_url: me.html_url },
		};
	},
});

const repoGetTool = defineTool({
	name: "gitcode_repo_get",
	label: "GitCode: repo info",
	description: "Get metadata for a GitCode repository (default branch, visibility, clone URLs).",
	parameters: Type.Object({
		owner: Type.String({ description: "Repository owner/namespace" }),
		repo: Type.String({ description: "Repository name" }),
	}),
	async execute(_id, p) {
		const r = await getRepo(p.owner, p.repo);
		return {
			content: text(
				`${r.full_name}\ndefault: ${r.default_branch}  private: ${r.private}\nssh: ${r.ssh_url_to_repo ?? ""}\nweb: ${r.web_url ?? ""}`,
			),
			details: r,
		};
	},
});

const branchesTool = defineTool({
	name: "gitcode_branches",
	label: "GitCode: branches",
	description: "List branches of a GitCode repository.",
	parameters: Type.Object({
		owner: Type.String({ description: "Repository owner/namespace" }),
		repo: Type.String({ description: "Repository name" }),
	}),
	async execute(_id, p) {
		const branches = await listBranches(p.owner, p.repo);
		const names = branches.map((b) => (b.default_branch ? `${b.name} (default)` : b.name));
		return {
			content: text(names.length ? names.join("\n") : "(no branches)"),
			details: { branches: names },
		};
	},
});

const forkTool = defineTool({
	name: "gitcode_fork",
	label: "GitCode: fork",
	description:
		"Fork a GitCode repository into a namespace (default: your account) and return the fork. Idempotent: returns the existing fork if one is already present.",
	promptGuidelines: [
		"Fork with gitcode_fork before pushing a branch, then clone the returned fork's ssh_url_to_repo and add the original repository as an `upstream` remote.",
	],
	parameters: Type.Object({
		owner: Type.String({ description: "Upstream repository owner/namespace" }),
		repo: Type.String({ description: "Upstream repository name" }),
		namespace: Type.Optional(Type.String({ description: "Destination namespace (default: your account)" })),
	}),
	async execute(_id, p) {
		const fork = await forkRepo(p.owner, p.repo, p.namespace);
		return {
			content: text(`Fork ready: ${fork.full_name}\nssh: ${fork.ssh_url_to_repo ?? ""}\nweb: ${fork.web_url ?? ""}`),
			details: fork,
		};
	},
});

const prCreateTool = defineTool({
	name: "gitcode_pr_create",
	label: "GitCode: open PR",
	description:
		"Open a pull request on GitCode. `head` is the source branch; when it lives in a fork use `<owner>:<branch>`.",
	promptGuidelines: [
		"Open pull requests with gitcode_pr_create after pushing the branch; pass head as `<your-login>:<branch>` when the branch is on a fork.",
	],
	parameters: Type.Object({
		owner: Type.String({ description: "Target (upstream) repository owner" }),
		repo: Type.String({ description: "Target repository name" }),
		title: Type.String({ description: "Pull request title" }),
		head: Type.String({ description: "Source branch, `<owner>:<branch>` for a fork" }),
		base: Type.String({ description: "Target branch, e.g. main or master" }),
		body: Type.Optional(Type.String({ description: "Pull request description" })),
		draft: Type.Optional(Type.Boolean({ description: "Open as a draft" })),
	}),
	async execute(_id, p) {
		const pr = await createPr({
			owner: p.owner,
			repo: p.repo,
			title: p.title,
			head: p.head,
			base: p.base,
			body: p.body,
			draft: p.draft,
		});
		return {
			content: text(`Opened PR #${pr.number}: ${pr.title}\n${pr.web_url ?? ""}`),
			details: pr,
		};
	},
});

const prListTool = defineTool({
	name: "gitcode_pr_list",
	label: "GitCode: list PRs",
	description: "List pull requests of a GitCode repository.",
	parameters: Type.Object({
		owner: Type.String({ description: "Repository owner/namespace" }),
		repo: Type.String({ description: "Repository name" }),
		state: Type.Optional(
			Type.Union([Type.Literal("open"), Type.Literal("closed"), Type.Literal("all")], {
				description: "Filter by state (default: open)",
			}),
		),
	}),
	async execute(_id, p) {
		const prs = await listPrs(p.owner, p.repo, p.state ?? "open");
		const lines = prs.map(
			(pr) => `#${pr.number} [${pr.state ?? "?"}] ${pr.title}  (${pr.source_branch ?? "?"} -> ${pr.target_branch ?? "?"})`,
		);
		return {
			content: text(lines.length ? lines.join("\n") : "(no pull requests)"),
			details: { count: prs.length, pullRequests: prs },
		};
	},
});

const prGetTool = defineTool({
	name: "gitcode_pr_get",
	label: "GitCode: PR details",
	description: "Get a single pull request by number.",
	parameters: Type.Object({
		owner: Type.String({ description: "Repository owner/namespace" }),
		repo: Type.String({ description: "Repository name" }),
		number: Type.Number({ description: "Pull request number" }),
	}),
	async execute(_id, p) {
		const pr = await getPr(p.owner, p.repo, p.number);
		return {
			content: text(
				`PR #${pr.number}: ${pr.title}\nstate: ${pr.state ?? "?"}\nbranch: ${pr.source_branch ?? "?"} -> ${pr.target_branch ?? "?"}\n${pr.web_url ?? ""}`,
			),
			details: pr,
		};
	},
});

export default function (pi: ExtensionAPI) {
	for (const tool of [whoamiTool, repoGetTool, branchesTool, forkTool, prCreateTool, prListTool, prGetTool]) {
		pi.registerTool(tool);
	}

	pi.registerCommand("gitcode", {
		description: "Show the authenticated GitCode user and token status",
		handler: async (_args, ctx) => {
			try {
				const me = await whoami();
				ctx.ui.notify(`GitCode: ${me.login}\n${me.html_url ?? ""}`, "info");
			} catch (err) {
				const message = err instanceof GitCodeError ? err.message : String(err);
				ctx.ui.notify(`GitCode not ready: ${message}`, "error");
			}
		},
	});
}
