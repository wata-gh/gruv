'use client';

import * as React from 'react';
import useSWR from 'swr';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Separator } from '@/components/ui/separator';
import { Skeleton } from '@/components/ui/skeleton';
import { ThemeToggle } from '@/components/theme-toggle';
import { cn } from '@/lib/utils';

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:9292';

interface RepositorySummary {
  organization: string;
  repository: string;
  latest_date: string;
  latest_filename: string;
  available_dates: string[];
}

interface RepositoriesResponse {
  repositories: RepositorySummary[];
}

interface HistoryItem {
  organization: string;
  repository: string;
  date: string;
  filename: string;
}

interface HistoryResponse {
  repository: {
    organization: string;
    name: string;
  };
  history: HistoryItem[];
}

interface SummaryResponse {
  repository: {
    organization: string;
    name: string;
  };
  summary: {
    date: string;
    filename: string;
    markdown: string;
    html: string;
  };
}

interface GenerateSummaryResponse {
  message: string;
  repository: {
    organization: string;
    repository: string;
  };
  output_path?: string;
  output_filename?: string;
  thread_id?: string;
  stdout?: string;
  stderr?: string;
}

const fetcher = async (url: string) => {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Request failed: ${response.status}`);
  }
  return response.json();
};

function formatRepositoryId(organization: string, repository: string) {
  return `${organization}/${repository}`;
}

function formatDateLabel(date: string) {
  try {
    return new Date(date).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  } catch (error) {
    return date;
  }
}

function useRepositorySelection(repositories?: RepositorySummary[]) {
  const [selectedId, setSelectedId] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (!repositories?.length) {
      return;
    }

    const defaultRepo = repositories[0];
    const defaultId = formatRepositoryId(defaultRepo.organization, defaultRepo.repository);
    setSelectedId((current) => current ?? defaultId);
  }, [repositories]);

  const selectedRepo = React.useMemo(() => {
    if (!repositories) {
      return null;
    }
    return repositories.find((repo) => formatRepositoryId(repo.organization, repo.repository) === selectedId) ?? null;
  }, [repositories, selectedId]);

  return {
    selectedRepo,
    selectRepo: (repo: RepositorySummary) => setSelectedId(formatRepositoryId(repo.organization, repo.repository)),
    selectById: (id: string | null) => setSelectedId(id)
  };
}

function MarkdownRenderer({ html, markdown }: { html?: string; markdown: string }) {
  if (html) {
    return <div dangerouslySetInnerHTML={{ __html: html }} />;
  }

  return <div className="whitespace-pre-wrap">{markdown}</div>;
}

export default function HomePage() {
  const {
    data: repositoriesData,
    error: repositoriesError,
    isLoading: repositoriesLoading,
    mutate: mutateRepositories
  } = useSWR<RepositoriesResponse>(`${API_BASE_URL}/repos`, fetcher, { refreshInterval: 60_000 });

  const repositories = repositoriesData?.repositories ?? [];
  const { selectedRepo, selectRepo, selectById } = useRepositorySelection(repositories);

  const [selectedDate, setSelectedDate] = React.useState<string | null>(null);
  const [showCreateForm, setShowCreateForm] = React.useState(false);
  const [newRepoUrl, setNewRepoUrl] = React.useState('');
  const [isCreating, setIsCreating] = React.useState(false);
  const [updatingRepoId, setUpdatingRepoId] = React.useState<string | null>(null);
  const [statusMessage, setStatusMessage] = React.useState<{ type: 'success' | 'error'; text: string } | null>(null);

  const selectedRepoId = React.useMemo(() => {
    if (!selectedRepo) {
      return null;
    }
    return formatRepositoryId(selectedRepo.organization, selectedRepo.repository);
  }, [selectedRepo]);

  const isSelectedRepoUpdating = selectedRepoId !== null && updatingRepoId === selectedRepoId;

  React.useEffect(() => {
    if (!statusMessage) {
      return;
    }
    const timer = window.setTimeout(() => setStatusMessage(null), 8000);
    return () => window.clearTimeout(timer);
  }, [statusMessage]);

  const repoHistoryKey = React.useMemo(() => {
    if (!selectedRepo) {
      return null;
    }
    return `${API_BASE_URL}/repos/${encodeURIComponent(selectedRepo.organization)}/${encodeURIComponent(selectedRepo.repository)}/history`;
  }, [selectedRepo]);

  const {
    data: historyData,
    error: historyError,
    mutate: mutateHistory
  } = useSWR<HistoryResponse>(repoHistoryKey, fetcher, {
    revalidateOnFocus: false
  });

  React.useEffect(() => {
    if (!historyData?.history?.length) {
      return;
    }
    const latest = historyData.history[0];
    setSelectedDate((current) => current ?? latest.date);
  }, [historyData]);

  const summaryKey = React.useMemo(() => {
    if (!selectedRepo || !selectedDate) {
      return null;
    }
    return `${API_BASE_URL}/repos/${encodeURIComponent(selectedRepo.organization)}/${encodeURIComponent(selectedRepo.repository)}/${selectedDate}`;
  }, [selectedRepo, selectedDate]);

  const {
    data: summaryData,
    error: summaryError,
    isLoading: summaryLoading,
    mutate: mutateSummary
  } = useSWR<SummaryResponse>(summaryKey, fetcher, {
    revalidateOnFocus: false
  });

  const triggerGeneration = React.useCallback(async (payload: Record<string, string>): Promise<GenerateSummaryResponse> => {
    const response = await fetch(`${API_BASE_URL}/repos/generate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    let data: unknown;
    try {
      data = await response.json();
    } catch (error) {
      data = undefined;
    }

    if (!response.ok) {
      const message = typeof data === 'object' && data !== null && 'error' in data && typeof (data as { error: unknown }).error === 'string'
        ? (data as { error: string }).error
        : 'Failed to generate summary.';
      throw new Error(message);
    }

    return data as GenerateSummaryResponse;
  }, []);

  const handleUpdateRepository = React.useCallback(
    async (repo: RepositorySummary) => {
      const repoId = formatRepositoryId(repo.organization, repo.repository);
      setStatusMessage(null);
      setUpdatingRepoId(repoId);

      try {
        const result = await triggerGeneration({ organization: repo.organization, repository: repo.repository });
        const messageSuffix = result.output_filename ? ` (${result.output_filename})` : '';
        setStatusMessage({ type: 'success', text: `Summary generated for ${repoId}${messageSuffix}.` });
        await mutateRepositories();

        if (selectedRepo && formatRepositoryId(selectedRepo.organization, selectedRepo.repository) === repoId) {
          setSelectedDate(null);
          await Promise.all([mutateHistory(), mutateSummary()]);
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to generate summary.';
        setStatusMessage({ type: 'error', text: message });
      } finally {
        setUpdatingRepoId(null);
      }
    },
    [mutateHistory, mutateRepositories, mutateSummary, selectedRepo, triggerGeneration]
  );

  const handleCreateRepository = React.useCallback(async () => {
    const trimmed = newRepoUrl.trim();
    if (!trimmed) {
      setStatusMessage({ type: 'error', text: 'Repository URL is required.' });
      return;
    }

    setStatusMessage(null);
    setIsCreating(true);

    try {
      const result = await triggerGeneration({ url: trimmed });
      const repoId = formatRepositoryId(result.repository.organization, result.repository.repository);
      const messageSuffix = result.output_filename ? ` (${result.output_filename})` : '';
      setStatusMessage({ type: 'success', text: `Summary generated for ${repoId}${messageSuffix}.` });
      setNewRepoUrl('');
      setShowCreateForm(false);
      selectById(repoId);
      setSelectedDate(null);
      await mutateRepositories();
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to generate summary.';
      setStatusMessage({ type: 'error', text: message });
    } finally {
      setIsCreating(false);
    }
  }, [mutateRepositories, newRepoUrl, selectById, triggerGeneration]);

  const isReady = !repositoriesLoading && !summaryLoading;

  return (
    <main className="flex min-h-screen flex-col bg-background text-foreground">
      <header className="flex items-center justify-between border-b px-8 py-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">GitHub Repository Update Viewer</h1>
          <p className="text-sm text-muted-foreground">Browse curated Markdown summaries across your favorite repositories.</p>
        </div>
        <ThemeToggle />
      </header>

      <div className="flex flex-1 flex-col gap-6 px-8 pb-8 pt-6 lg:flex-row">
        <Card className="w-full flex-none lg:w-72">
          <CardHeader>
            <CardTitle className="text-lg">Repositories</CardTitle>
            <CardDescription>Select a repository to explore summaries.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4 pt-2">
            {repositoriesLoading && <Skeleton className="h-10 w-full" />}
            {repositoriesError && <p className="text-sm text-destructive">Failed to load repositories. Please try again.</p>}

            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Manage</span>
              <Button
                type="button"
                variant="outline"
                size="icon"
                aria-label={showCreateForm ? 'Hide repository creation form' : 'Add repository'}
                onClick={() => setShowCreateForm((previous) => !previous)}
              >
                <span className="text-lg leading-none">+</span>
              </Button>
            </div>

            {showCreateForm && (
              <div className="space-y-2">
                <input
                  value={newRepoUrl}
                  onChange={(event) => setNewRepoUrl(event.target.value)}
                  placeholder="https://github.com/organization/repository"
                  className="h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                  type="url"
                  autoComplete="off"
                />
                <div className="flex items-center gap-2">
                  <Button type="button" onClick={handleCreateRepository} disabled={isCreating}>
                    {isCreating ? 'Creating…' : 'Create'}
                  </Button>
                  <Button type="button" variant="ghost" onClick={() => setShowCreateForm(false)} disabled={isCreating}>
                    Cancel
                  </Button>
                </div>
              </div>
            )}

            {statusMessage && (
              <div
                className={cn(
                  'rounded-md border px-3 py-2 text-sm',
                  statusMessage.type === 'error'
                    ? 'border-destructive/40 bg-destructive/10 text-destructive'
                    : 'border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300'
                )}
              >
                {statusMessage.text}
              </div>
            )}

            <ScrollArea className="h-[60vh]">
              <div className="flex flex-col gap-2">
                {repositories.map((repo) => {
                  const id = formatRepositoryId(repo.organization, repo.repository);
                  const isActive = selectedRepo && id === formatRepositoryId(selectedRepo.organization, selectedRepo.repository);
                  const isUpdating = updatingRepoId === id;
                  return (
                    <div key={id} className="flex items-start gap-2">
                      <button
                        type="button"
                        onClick={() => {
                          selectRepo(repo);
                          setSelectedDate(null);
                        }}
                        className={cn(
                          'flex flex-1 flex-col rounded-md border px-3 py-2 text-left transition hover:border-accent hover:bg-accent',
                          isActive ? 'border-primary bg-primary/10 text-primary-foreground dark:bg-primary/20' : 'border-border'
                        )}
                      >
                        <span className="text-sm font-medium">
                          {repo.organization}/{repo.repository}
                        </span>
                        <span className="text-xs text-muted-foreground">
                          {isUpdating ? 'Updating…' : `Latest ${repo.latest_date ? formatDateLabel(repo.latest_date) : '—'}`}
                        </span>
                      </button>
                    </div>
                  );
                })}
              </div>
            </ScrollArea>
          </CardContent>
        </Card>

        <div className="flex min-h-[60vh] flex-1 flex-col gap-6">
          <Card className="flex-1">
            <CardHeader className="flex flex-row items-center justify-between space-y-0">
              <div>
                <CardTitle className="text-lg">
                  {selectedRepo ? `${selectedRepo.organization}/${selectedRepo.repository}` : 'Select a repository'}
                </CardTitle>
                <CardDescription>
                  {selectedDate ? `Summary for ${formatDateLabel(selectedDate)}` : 'Choose a repository to view the latest summary.'}
                </CardDescription>
              </div>
              {summaryData?.summary?.filename && (
                <span className="text-xs text-muted-foreground">{summaryData.summary.filename}</span>
              )}
            </CardHeader>
            <Separator className="mb-6" />
            <CardContent className="pt-0">
              {!isReady && <Skeleton className="h-96 w-full" />}
              {summaryError && (
                <p className="rounded-md border border-destructive/40 bg-destructive/10 p-4 text-sm text-destructive">
                  Failed to load summary. Please select another entry or try again later.
                </p>
              )}
              {summaryData?.summary && (
                <article className="markdown-content">
                  <MarkdownRenderer html={summaryData.summary.html} markdown={summaryData.summary.markdown} />
                </article>
              )}
            </CardContent>
          </Card>
        </div>

        <Card className="w-full flex-none lg:w-72">
          <CardHeader className="flex flex-row items-center justify-between space-y-0">
            <div>
              <CardTitle className="text-lg">History</CardTitle>
              <CardDescription>Previous summaries for quick context.</CardDescription>
            </div>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={!selectedRepo || isSelectedRepoUpdating}
              onClick={() => {
                if (selectedRepo) {
                  handleUpdateRepository(selectedRepo);
                }
              }}
            >
              {isSelectedRepoUpdating ? 'Generating…' : 'Generate latest'}
            </Button>
          </CardHeader>
          <CardContent className="pt-2">
            {!selectedRepo && <p className="text-sm text-muted-foreground">Choose a repository to view its history.</p>}
            {historyError && (
              <p className="text-sm text-destructive">Failed to load history.</p>
            )}
            <ScrollArea className="h-[60vh]">
              <div className="flex flex-col gap-2">
                {historyData?.history?.map((entry) => {
                  const isActive = selectedDate === entry.date;
                  return (
                    <Button
                      key={entry.filename}
                      variant={isActive ? 'default' : 'ghost'}
                      className="justify-start"
                      onClick={() => setSelectedDate(entry.date)}
                    >
                      <div className="flex flex-col items-start">
                        <span className="text-sm font-medium">{formatDateLabel(entry.date)}</span>
                        <span className="text-xs text-muted-foreground">{entry.filename}</span>
                      </div>
                    </Button>
                  );
                })}
              </div>
            </ScrollArea>
          </CardContent>
        </Card>
      </div>
    </main>
  );
}
