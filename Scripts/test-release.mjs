import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { Writable } from "node:stream";
import { generateNotes } from "@semantic-release/release-notes-generator";
import semanticRelease from "semantic-release";
import config from "../release.config.mjs";
import { verifyRelease } from "./semantic-release-plugin.mjs";
import { analyzeCommits } from "@semantic-release/commit-analyzer";

const logger = { log() {}, error() {}, success() {} };
const analysis = config.plugins[0][1];
const analyze = messages => analyzeCommits(analysis, {
  cwd: process.cwd(), logger, lastRelease: { version: "1.0.0" },
  commits: messages.map((message, index) => ({ message, hash: String(index + 1).repeat(40) })).reverse(),
});

async function testPolicy() {
  for (const type of ["fix", "perf", "revert", "chore", "refactor", "build"]) {
    assert.equal(await analyze([`${type}: maintain app`]), "patch");
  }
  for (const type of ["ci", "config", "docs", "style", "test"]) {
    assert.equal(await analyze([`${type}: maintain app`]), null);
    assert.equal(await analyze([`${type}!: change contract`]), "major");
  }
  assert.equal(await analyze(["feat: add input", "fix: repair installation"]), "minor");
  assert.equal(await analyze(["fix: change contract\n\nBREAKING CHANGE: input removed"]), "major");
  assert.equal(await analyze([
    "feat(app): add input",
    `revert(app): feat(app): add input\n\nThis reverts commit ${"1".repeat(40)}.`,
  ]), null);
  assert.equal(await analyze(["fix(deps): patch a runtime security vulnerability"]), "patch");
  assert.equal(await analyze(["chore(deps): update release tooling"]), "patch");
}

await testPolicy();
{
  const root = mkdtempSync(path.join(tmpdir(), "passing-by-release-"));
  const cwd = path.join(root, "checkout");
  const remote = path.join(root, "remote.git");
  // Never inherit CI credentials or workflow metadata into the offline engine.
  const env = {
    PATH: process.env.PATH,
    HOME: root,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: path.join(root, "empty-config"),
    GIT_TERMINAL_PROMPT: "0",
  };
  const git = (...args) => execFileSync("git", args, { cwd, env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  try {
    execFileSync("git", ["init", "--bare", "--initial-branch=main", remote], { env, stdio: "pipe" });
    execFileSync("git", ["clone", remote, cwd], { env, stdio: "pipe" });
    git("config", "user.name", "Release Fixture");
    git("config", "user.email", "fixture@example.invalid");
    let count = 0;
    const commit = message => {
      writeFileSync(path.join(cwd, "fixture"), String(++count));
      git("add", "fixture");
      git("commit", "-m", message);
      git("push", "origin", "main");
    };
    const published = [];
    const sink = new Writable({ write(_chunk, _encoding, done) { done(); } });
    const run = (version, dryRun = false, overrides = {}) => semanticRelease({
      dryRun,
      ...config,
      ci: false,
      repositoryUrl: remote,
      plugins: [
        ["@semantic-release/commit-analyzer", analysis],
        { generateNotes: (_options, context) => generateNotes(config.plugins[1][1], {
          ...context, options: { ...context.options, repositoryUrl: config.repositoryUrl },
        }) },
        ...(dryRun ? [] : [{ verifyRelease }]),
        { publish: async (_options, context) => {
          published.push({ ...context.nextRelease });
          return { name: "Offline publication fixture" };
        } },
      ],
    }, { cwd, env: { ...env, GITHUB_SHA: git("rev-parse", "HEAD"),
      EXPECTED_RELEASE_VERSION: version, ...overrides }, stdout: sink, stderr: sink });

    commit("feat: initial release of Passing By");
    const initialHead = git("rev-parse", "HEAD");
    assert.equal(git("tag"), "");
    const preview = await run("1.0.0", true);
    assert.equal(preview.nextRelease.version, "1.0.0");
    assert.equal(git("tag"), "");
    assert.equal(published.length, 0);
    await assert.rejects(run("9.9.9"), /version changed/);
    await assert.rejects(run("1.0.0", false, { GITHUB_SHA: "0".repeat(40) }), /main changed/);
    assert.equal(git("tag"), "");
    const first = await run("1.0.0");
    assert.equal(first.nextRelease.version, "1.0.0");
    assert.equal(first.nextRelease.gitTag, "v1.0.0");
    assert.equal(git("ls-remote", "--tags", "origin"), `${initialHead}\trefs/tags/v1.0.0`);
    assert.equal(git("rev-parse", "HEAD"), initialHead);
    assert.equal(git("status", "--porcelain"), "");
    assert.equal(published[0].gitHead, initialHead);
    assert.match(published[0].notes, /initial release of Passing By/);
    assert.equal(await run("1.0.0"), false);
    assert.equal(published.length, 1);

    commit("fix(app): preserve status");
    const testedHead = git("rev-parse", "HEAD");
    execFileSync("git", ["--git-dir", remote, "update-ref", "refs/heads/main", initialHead], { env });
    assert.throws(() => verifyRelease({}, { cwd, env: { ...env, GITHUB_SHA: testedHead,
      EXPECTED_RELEASE_VERSION: "1.0.1" }, nextRelease: { version: "1.0.1" } }), /main changed/);
    assert.equal(git("tag"), "v1.0.0");
    execFileSync("git", ["--git-dir", remote, "update-ref", "refs/heads/main", testedHead], { env });
    assert.equal((await run("1.0.1")).nextRelease.version, "1.0.1");
    commit("feat(app): extend installation");
    assert.equal((await run("1.1.0")).nextRelease.version, "1.1.0");
    commit("feat(app)!: change input contract");
    assert.equal((await run("2.0.0")).nextRelease.version, "2.0.0");
    commit("docs: explain input");
    assert.equal(await run("2.0.0", true), false);
    assert.equal(await run("2.0.0"), false);
    assert.equal(published.length, 4);
    assert.equal(git("tag"), "v1.0.0\nv1.0.1\nv1.1.0\nv2.0.0");
    assert.equal(git("rev-list", "--count", "HEAD"), "5");
    assert.equal(git("status", "--porcelain"), "");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
console.log("Release policy and offline Semantic Release lifecycle passed.");
