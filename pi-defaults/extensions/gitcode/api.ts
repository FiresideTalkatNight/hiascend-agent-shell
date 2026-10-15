/**
 * GitCode API wrapper for the `gitcode` Pi extension.
 *
 * This module deliberately has NO Pi imports, so it can be exercised with plain
 * Node (see `selftest.ts`) as well as loaded by Pi. It shells out to the
 * `gitcode-api` CLI, which mirrors the GitCode REST API and emits JSON.
 *
 * Authentication uses the `GITCODE_ACCESS_TOKEN` environment variable, exactly
 * like the CLI itself.
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const BIN = process.env.GITCODE_API_BIN ?? "gitcode-api";

export class GitCodeError extends Error {
	constructor(message: string) {
		super(message);
		this.name = "GitCodeError";
	}
}

/** Run `gitcode-api <args...> --compact` and parse the JSON response. */
export async function gitcodeApi<T = unknown>(args: string[]): Promise<T> {
	if (!process.env.GITCODE_ACCESS_TOKEN) {
		throw new GitCodeError(
			"GITCODE_ACCESS_TOKEN is not set. Provide a GitCode access token in the environment.",
		);
	}
	try {
		const { stdout } = await execFileAsync(BIN, [...args, "--compact"], {
			maxBuffer: 64 * 1024 * 1024,
			env: process.env,
		});
		const text = stdout.trim();
		return (text ? JSON.parse(text) : null) as T;
	} catch (err: unknown) {
		const e = err as { stderr?: string; stdout?: string; message?: string };
		const detail = String(e.stderr || e.stdout || e.message || err).trim();
		throw new GitCodeError(detail.slice(0, 1500) || `${BIN} failed`);
	}
}

export interface User {
	login: string;
	name?: string;
	id?: string | number;
	html_url?: string;
	email?: string;
}

export interface Repo {
	full_name: string;
	default_branch?: string;
	private?: boolean;
	fork?: boolean;
	ssh_url_to_repo?: string;
	web_url?: string;
}

export interface Branch {
	name: string;
	default_branch?: boolean;
}

export interface PullRequest {
	number: number;
	title: string;
	state?: string;
	web_url?: string;
	source_branch?: string;
	target_branch?: string;
}

export const whoami = () => gitcodeApi<User>(["users", "me"]);

export const getRepo = (owner: string, repo: string) =>
	gitcodeApi<Repo>(["repos", "get", "--owner", owner, "--repo", repo]);

/**
 * Fork `owner/repo` into `namespace` (default: the authenticated user) and
 * return the resulting repository. Idempotent: an existing fork is returned as
 * well, since the create call fails in that case.
 */
export async function forkRepo(owner: string, repo: string, namespace?: string): Promise<Repo> {
	const args = ["repos", "fork", "--owner", owner, "--repo", repo];
	if (namespace) args.push("--namespace", namespace);

	try {
		const created = await gitcodeApi<Repo>(args);
		if (created?.full_name) return created;
	} catch {
		// A pre-existing fork, or eventual consistency; resolve it below.
	}

	const targetOwner = namespace ?? (await whoami()).login;
	let lastError: unknown;
	for (let attempt = 0; attempt < 10; attempt++) {
		try {
			return await getRepo(targetOwner, repo);
		} catch (err) {
			lastError = err;
			await new Promise((resolve) => setTimeout(resolve, 2000));
		}
	}
	throw new GitCodeError(
		`fork of ${owner}/${repo} was not found under ${targetOwner}${lastError ? `: ${lastError}` : ""}`,
	);
}

export const listBranches = (owner: string, repo: string) =>
	gitcodeApi<Branch[]>(["branches", "list", "--owner", owner, "--repo", repo]);

export interface CreatePrInput {
	owner: string;
	repo: string;
	title: string;
	head: string;
	base: string;
	body?: string;
	draft?: boolean;
}

export function createPr(input: CreatePrInput) {
	const args = [
		"pulls",
		"create",
		"--owner",
		input.owner,
		"--repo",
		input.repo,
		"--title",
		input.title,
		"--head",
		input.head,
		"--base",
		input.base,
	];
	if (input.body) args.push("--body", input.body);
	if (input.draft) args.push("--draft");
	return gitcodeApi<PullRequest>(args);
}

export const listPrs = (owner: string, repo: string, state = "open", perPage = 30) =>
	gitcodeApi<PullRequest[]>([
		"pulls",
		"list",
		"--owner",
		owner,
		"--repo",
		repo,
		"--state",
		state,
		"--per-page",
		String(perPage),
	]);

export const getPr = (owner: string, repo: string, number: number) =>
	gitcodeApi<PullRequest>(["pulls", "get", "--owner", owner, "--repo", repo, "--number", String(number)]);
