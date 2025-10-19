#!/usr/bin/env node

import { Codex } from "@openai/codex-sdk";
import { readFile, writeFile, mkdir, appendFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, "..");
const LOG_DIR = path.join(REPO_ROOT, "logs");
const LOG_FILE = path.join(LOG_DIR, "update_summary.log");

async function ensureLogSetup() {
  await mkdir(LOG_DIR, { recursive: true });
}

async function writeLog(message) {
  await ensureLogSetup();
  const timestamp = new Date().toISOString();
  await appendFile(LOG_FILE, `[${timestamp}] ${message}\n`);
}

async function writeLogBlock(header, body) {
  await ensureLogSetup();
  const timestamp = new Date().toISOString();
  const normalizedBody = `${body}`.replace(/\r\n/g, "\n");
  const entry = `[${timestamp}] ${header}\n${normalizedBody}\n`;
  await appendFile(LOG_FILE, entry);
}

async function logAndExit(message, error) {
  console.error(message);
  if (error) {
    console.error(error);
  }
  try {
    const errorDetails = error
      ? `${message} | ${error.stack ?? error.message ?? String(error)}`
      : message;
    await writeLog(`ERROR ${errorDetails}`);
  } catch (logError) {
    console.error("Failed to write log entry:", logError);
  }
  process.exit(1);
}

async function main() {
  const startTime = Date.now();
  const [organization, repository] = process.argv.slice(2);

  if (!organization || !repository) {
    console.error("Usage: generate_summary.mjs <organization> <repository>");
    process.exit(1);
  }

  const today = new Date().toISOString().slice(0, 10);
  const outputFile = `${organization}_${repository}_${today}.md`;
  const outputPath = path.join(REPO_ROOT, outputFile);
  const templatePath = path.join(REPO_ROOT, "template.md");

  await writeLog(
    `START organization=${organization} repository=${repository} output=${outputFile}`
  );

  let template;
  try {
    template = await readFile(templatePath, "utf8");
  } catch (error) {
    await logAndExit(`Failed to read template at ${templatePath}`, error);
  }

  const prompt = [
    `https://github.com/${organization}/${repository} のリポジトリについて`,
    "直近１ヶ月の開発状況とリリースについてわかりやすい日本語でまとめてください。",
    "最終的なMarkdown本文のみを出力し、余計な説明は加えないでください。",
    "フォーマットは以下を使用し、issue/discussion/pull-request にはリンクを貼ってください。",
    template.trim(),
  ].join("\n\n");

  const codex = new Codex();
  const thread = codex.startThread({
    workingDirectory: REPO_ROOT,
    sandboxMode: "danger-full-access",
    skipGitRepoCheck: true,
  });

  let turn;
  try {
    turn = await thread.run(prompt);
  } catch (error) {
    await logAndExit("Codex failed to generate the summary", error);
  }

  const content = turn.finalResponse?.trim();
  if (!content) {
    await logAndExit("Codex returned an empty response.");
  }

  await writeLogBlock(
    `LLM_OUTPUT organization=${organization} repository=${repository} thread=${thread.id ?? "unknown"}`,
    content
  );

  const durationMs = Date.now() - startTime;
  const totalSeconds = Math.max(0, Math.round(durationMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  const formattedDuration = `作成時間: ${minutes} 分 ${seconds
    .toString()
    .padStart(2, "0")} 秒`;

  const outputWithDuration = `${formattedDuration}\n\n${content}`;

  try {
    await writeFile(outputPath, outputWithDuration, "utf8");
  } catch (error) {
    await logAndExit(`Failed to write summary to ${outputPath}`, error);
  }

  await writeLog(
    `SUCCESS organization=${organization} repository=${repository} output=${outputFile} thread=${thread.id ?? "unknown"}`
  );

  console.log(`Summary written to ${outputPath}`);
  if (thread.id) {
    console.log(`Thread ID: ${thread.id}`);
  }
}

await main();
