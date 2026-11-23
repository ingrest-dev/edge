const REPO = "ingrest-dev/edge";
const UA = "edge-watch-trigger";

function newer(a, b) {
  const x = a.split(".").map(Number);
  const y = b.split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] ?? 0) - (y[i] ?? 0);
    if (d !== 0) return d > 0;
  }
  return false;
}

function gh(env, path, init = {}) {
  return fetch(`https://api.github.com${path}`, {
    ...init,
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      "user-agent": UA,
      "x-github-api-version": "2022-11-28",
      ...init.headers,
    },
  });
}

export async function check(env) {
  const page = await fetch("https://nginx.org/en/download.html", { headers: { "user-agent": UA } });
  if (!page.ok) throw new Error(`nginx.org download page: ${page.status}`);
  const section = (await page.text()).match(/Mainline version(.*?)Stable version/s)?.[1] ?? "";
  const latest = section.match(/nginx-(\d+\.\d+\.\d+)\.tar\.gz/)?.[1];
  if (!latest) throw new Error("no mainline version on nginx.org");

  const res = await gh(env, `/repos/${REPO}/contents/VERSION?ref=main`, { headers: { accept: "application/vnd.github.raw" } });
  if (!res.ok) throw new Error(`VERSION: ${res.status}`);
  const current = (await res.text()).trim().replace(/\.\d+$/, "");
  if (!newer(latest, current)) return `nginx ${current} is the latest mainline`;

  const sig = await fetch(`https://nginx.org/download/nginx-${latest}.tar.gz.asc`, { method: "HEAD", headers: { "user-agent": UA } });
  if (!sig.ok) return `nginx ${latest} has no signature yet`;

  const branch = await gh(env, `/repos/${REPO}/branches/nginx-${latest}`);
  if (branch.ok) return `branch nginx-${latest} exists`;
  if (branch.status !== 404) throw new Error(`branch nginx-${latest}: ${branch.status}`);

  const runs = await gh(env, `/repos/${REPO}/actions/workflows/watch.yml/runs?per_page=1`);
  if (!runs.ok) throw new Error(`watch runs: ${runs.status}`);
  const last = (await runs.json()).workflow_runs?.[0];
  if (last && last.status !== "completed") return `watch is ${last.status}`;
  if (last && last.conclusion === "failure" && Date.now() - Date.parse(last.created_at) < 3600_000) {
    return `watch failed at ${last.created_at}, next try an hour later`;
  }

  const run = await gh(env, `/repos/${REPO}/actions/workflows/watch.yml/dispatches`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ ref: "main" }),
  });
  if (!run.ok) throw new Error(`dispatch watch: ${run.status} ${await run.text()}`);
  return `nginx ${latest}: watch dispatched`;
}

export default {
  async scheduled(_controller, env) {
    console.log(await check(env));
  },
};
