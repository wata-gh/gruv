'use client';

import * as React from 'react';
import useSWR from 'swr';

import { FileText, ListTodo, Loader2, Plus, RefreshCcw, Settings } from 'lucide-react';

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

interface LogFileDescriptor {
  id: string;
  name: string;
  size: number;
  mtime: string;
}

interface LogsResponse {
  logs: LogFileDescriptor[];
}

interface LogStreamResponse {
  id: string;
  name: string;
  content: string;
  cursor: number;
  size: number;
  mtime: string;
  reset: boolean;
}

type ViewMode = 'summaries' | 'logs';

interface QueueJobDescriptor {
  organization: string;
  repository: string;
  enqueued_at?: string;
  started_at?: string;
}

interface QueueStatusResponse {
  size: number;
  active_job: QueueJobDescriptor | null;
  jobs: QueueJobDescriptor[];
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

function formatFileSize(bytes: number) {
  if (!Number.isFinite(bytes) || bytes < 0) {
    return '0 B';
  }

  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  const display = unitIndex === 0 ? Math.round(value).toString() : value.toFixed(1);
  return `${display} ${units[unitIndex]}`;
}

function formatDateTime(timestamp: string | null | undefined) {
  if (!timestamp) {
    return '—';
  }

  try {
    return new Date(timestamp).toLocaleString();
  } catch (error) {
    return timestamp;
  }
}

function formatLastUpdated(date: Date | null) {
  if (!date) {
    return 'Last refreshed: never';
  }

  return `Last refreshed: ${date.toLocaleString()}`;
}

function extractDateFromFilename(filename?: string | null) {
  if (!filename) {
    return null;
  }

  const match = filename.match(/\d{4}-\d{2}-\d{2}/);
  return match ? match[0] : null;
}

async function waitForSummaryAvailability(params: {
  organization: string;
  repository: string;
  expectedDate?: string | null;
  timeoutMs?: number;
  pollIntervalMs?: number;
}) {
  const {
    organization,
    repository,
    expectedDate,
    timeoutMs = 60_000,
    pollIntervalMs = 3_000
  } = params;

  const repoId = formatRepositoryId(organization, repository);
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    let summaryReady = false;

    if (expectedDate) {
      try {
        const historyResponse = await fetch(
          `${API_BASE_URL}/repos/${encodeURIComponent(organization)}/${encodeURIComponent(repository)}/history`
        );
        if (historyResponse.ok) {
          const historyData = (await historyResponse.json()) as HistoryResponse;
          summaryReady = historyData.history?.some((item) => item.date === expectedDate) ?? false;
        }
      } catch (error) {
        console.warn('Failed to check history while waiting for summary availability.', error);
      }

      if (!summaryReady) {
        try {
          const summaryResponse = await fetch(
            `${API_BASE_URL}/repos/${encodeURIComponent(organization)}/${encodeURIComponent(repository)}/${expectedDate}`
          );
          summaryReady = summaryResponse.ok;
        } catch (error) {
          console.warn('Failed to check summary while waiting for availability.', error);
        }
      }

      if (summaryReady) {
        return;
      }
    }

    try {
      const queueResponse = await fetch(`${API_BASE_URL}/queue`);
      if (queueResponse.ok) {
        const queueData = (await queueResponse.json()) as QueueStatusResponse;
        const isActive =
          queueData.active_job !== null &&
          formatRepositoryId(queueData.active_job.organization, queueData.active_job.repository) === repoId;
        const isQueued = queueData.jobs.some(
          (job) => formatRepositoryId(job.organization, job.repository) === repoId
        );

        if (!expectedDate && !isActive && !isQueued) {
          return;
        }

        if (expectedDate && !isActive && !isQueued) {
          // The job has finished processing but the summary has not appeared yet.
          // Allow another polling cycle to pick up the new entry before timing out.
        }
      }
    } catch (error) {
      console.warn('Failed to check queue while waiting for summary availability.', error);
    }

    await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
  }

  throw new Error('Timed out waiting for summary to become available. Please try again later.');
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

const LOG_STREAM_POLL_INTERVAL = 5000;

function useLogStream(logId: string | null, { enabled }: { enabled: boolean }) {
  const [content, setContent] = React.useState('');
  const [isFetching, setIsFetching] = React.useState(false);
  const [error, setError] = React.useState<Error | null>(null);
  const [lastUpdatedAt, setLastUpdatedAt] = React.useState<Date | null>(null);
  const cursorRef = React.useRef<number | null>(null);
  const mountedRef = React.useRef(true);

  React.useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  React.useEffect(() => {
    cursorRef.current = null;
    setContent('');
    setError(null);
    setLastUpdatedAt(null);
  }, [logId]);

  const fetchChunk = React.useCallback(
    async ({ reset = false }: { reset?: boolean } = {}) => {
      if (!logId) {
        return;
      }

      if (reset) {
        cursorRef.current = null;
      }

      const params = new URLSearchParams();
      const currentCursor = cursorRef.current;

      if (currentCursor !== null && !reset) {
        params.set('cursor', String(currentCursor));
      }

      const query = params.toString();
      const url = `${API_BASE_URL}/logs/${encodeURIComponent(logId)}${query ? `?${query}` : ''}`;

      try {
        setIsFetching(true);
        const response = await fetch(url);
        if (!response.ok) {
          throw new Error(`Failed to fetch log (${response.status})`);
        }

        const payload: LogStreamResponse = await response.json();

        if (!mountedRef.current) {
          return;
        }

        const chunk = payload.content ?? '';
        const shouldReset = reset || payload.reset;

        if (shouldReset) {
          setContent(chunk);
        } else if (chunk) {
          setContent((previous) => `${previous}${chunk}`);
        }

        const nextCursor =
          typeof payload.cursor === 'number' && Number.isFinite(payload.cursor)
            ? payload.cursor
            : typeof payload.size === 'number' && Number.isFinite(payload.size)
              ? payload.size
              : cursorRef.current;

        if (typeof nextCursor === 'number' && Number.isFinite(nextCursor)) {
          cursorRef.current = nextCursor;
        }

        let refreshedAt = new Date();
        if (typeof payload.mtime === 'string') {
          const parsed = new Date(payload.mtime);
          if (!Number.isNaN(parsed.getTime())) {
            refreshedAt = parsed;
          }
        }

        setLastUpdatedAt(refreshedAt);
        setError(null);
      } catch (fetchError) {
        if (!mountedRef.current) {
          return;
        }
        setError(fetchError instanceof Error ? fetchError : new Error('Failed to fetch log'));
      } finally {
        if (mountedRef.current) {
          setIsFetching(false);
        }
      }
    },
    [logId]
  );

  React.useEffect(() => {
    if (!enabled || !logId) {
      return;
    }

    fetchChunk({ reset: true }).catch(() => {
      /* handled in hook */
    });

    const interval = window.setInterval(() => {
      fetchChunk().catch(() => {
        /* handled in hook */
      });
    }, LOG_STREAM_POLL_INTERVAL);

    return () => {
      window.clearInterval(interval);
    };
  }, [enabled, fetchChunk, logId]);

  const reload = React.useCallback(() => fetchChunk({ reset: true }), [fetchChunk]);

  return {
    content,
    isFetching,
    error,
    reload,
    lastUpdatedAt,
    hasContent: content.length > 0
  } as const;
}

function SettingsMenu({ activeView, onSelectView }: { activeView: ViewMode; onSelectView: (view: ViewMode) => void }) {
  const [open, setOpen] = React.useState(false);
  const containerRef = React.useRef<HTMLDivElement | null>(null);

  React.useEffect(() => {
    if (!open) {
      return;
    }

    function handleClick(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }

    function handleKey(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        setOpen(false);
      }
    }

    document.addEventListener('mousedown', handleClick);
    document.addEventListener('keydown', handleKey);

    return () => {
      document.removeEventListener('mousedown', handleClick);
      document.removeEventListener('keydown', handleKey);
    };
  }, [open]);

  const handleSelect = React.useCallback(
    (view: ViewMode) => {
      onSelectView(view);
      setOpen(false);
    },
    [onSelectView]
  );

  const menuItems: { view: ViewMode; label: string; description: string }[] = [
    { view: 'summaries', label: 'Repository Viewer', description: 'Browse repository summaries' },
    { view: 'logs', label: 'View Logs', description: 'Monitor server log files' }
  ];

  return (
    <div className="relative" ref={containerRef}>
      <Button
        type="button"
        variant="ghost"
        size="icon"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label="Open settings menu"
        onClick={() => setOpen((previous) => !previous)}
      >
        <Settings className="h-4 w-4" aria-hidden="true" />
      </Button>
      {open && (
        <div className="absolute right-0 z-20 mt-2 w-64 rounded-md border bg-popover p-1 text-popover-foreground shadow-lg">
          {menuItems.map((item) => {
            const isActive = item.view === activeView;
            return (
              <button
                key={item.view}
                type="button"
                className={cn(
                  'flex w-full flex-col rounded-md px-3 py-2 text-left text-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  isActive ? 'bg-accent text-accent-foreground' : 'hover:bg-accent hover:text-accent-foreground'
                )}
                onClick={() => handleSelect(item.view)}
              >
                <span className="font-medium">{item.label}</span>
                <span className="text-xs text-muted-foreground">{item.description}</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

function QueueStatusMenu({
  status,
  isLoading,
  error
}: {
  status: QueueStatusResponse | undefined;
  isLoading: boolean;
  error: unknown;
}) {
  const [open, setOpen] = React.useState(false);
  const containerRef = React.useRef<HTMLDivElement | null>(null);

  React.useEffect(() => {
    if (!open) {
      return;
    }

    function handleClick(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }

    function handleKey(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        setOpen(false);
      }
    }

    document.addEventListener('mousedown', handleClick);
    document.addEventListener('keydown', handleKey);

    return () => {
      document.removeEventListener('mousedown', handleClick);
      document.removeEventListener('keydown', handleKey);
    };
  }, [open]);

  const queuedJobs = status?.jobs ?? [];
  const activeJob = status?.active_job ?? null;
  const queuedCount = typeof status?.size === 'number' ? status.size : queuedJobs.length;
  const displayCount = queuedCount;
  const hasError = Boolean(error);

  const isInitialLoading = isLoading && !status && !hasError;

  const ariaLabel = React.useMemo(() => {
    if (isInitialLoading) {
      return 'Queue status is loading';
    }
    if (hasError) {
      return 'Queue status is unavailable';
    }
    if (displayCount === 1) {
      return 'There is 1 job in the update queue';
    }
    return `There are ${displayCount} jobs in the update queue`;
  }, [displayCount, hasError, isInitialLoading]);

  const errorMessage = React.useMemo(() => {
    if (!error) {
      return null;
    }
    if (error instanceof Error) {
      return error.message;
    }
    return 'Failed to load queue status.';
  }, [error]);

  return (
    <div className="relative" ref={containerRef}>
      <Button
        type="button"
        variant="ghost"
        size="sm"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={ariaLabel}
        onClick={() => setOpen((previous) => !previous)}
        className="gap-2"
      >
        {isInitialLoading ? (
          <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
        ) : (
          <ListTodo className="h-4 w-4" aria-hidden="true" />
        )}
        <span className="text-sm font-medium">{hasError ? '—' : displayCount}</span>
      </Button>
      {open && (
        <div className="absolute right-0 z-20 mt-2 w-72 rounded-md border bg-popover p-3 text-popover-foreground shadow-lg">
          <div className="mb-2 text-sm font-semibold">Update queue</div>
          {isInitialLoading ? (
            <p className="text-sm text-muted-foreground">Loading queue status…</p>
          ) : hasError ? (
            <p className="text-sm text-destructive">{errorMessage}</p>
          ) : (
            <div className="space-y-3 text-sm">
              <div>
                <div className="text-xs uppercase tracking-wide text-muted-foreground">Active job</div>
                {activeJob ? (
                  <div className="mt-1 rounded-md border bg-background px-3 py-2">
                    <div className="font-medium">
                      {formatRepositoryId(activeJob.organization, activeJob.repository)}
                    </div>
                    <div className="text-xs text-muted-foreground">
                      {activeJob.enqueued_at ? (
                        <span className="block">Queued {formatDateTime(activeJob.enqueued_at)}</span>
                      ) : null}
                      <span>Started {formatDateTime(activeJob.started_at)}</span>
                    </div>
                  </div>
                ) : (
                  <p className="mt-1 text-muted-foreground">No job is currently running.</p>
                )}
              </div>
              <Separator />
              <div>
                <div className="flex items-center justify-between text-xs uppercase tracking-wide text-muted-foreground">
                  <span>Queued jobs</span>
                  <span>{queuedCount}</span>
                </div>
                {queuedJobs.length > 0 ? (
                  <div className="mt-2 max-h-48 space-y-2 overflow-y-auto pr-1">
                    {queuedJobs.map((job, index) => {
                      const identifier = formatRepositoryId(job.organization, job.repository);
                      return (
                        <div key={`${identifier}-${index}`} className="rounded-md border bg-background px-3 py-2">
                          <div className="font-medium">{identifier}</div>
                          <div className="text-xs text-muted-foreground">
                            Enqueued {formatDateTime(job.enqueued_at)}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                ) : (
                  <p className="mt-1 text-muted-foreground">Queue is empty.</p>
                )}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default function HomePage() {
  const [activeView, setActiveView] = React.useState<ViewMode>('summaries');
  const {
    data: repositoriesData,
    error: repositoriesError,
    isLoading: repositoriesLoading,
    mutate: mutateRepositories
  } = useSWR<RepositoriesResponse>(`${API_BASE_URL}/repos`, fetcher, { refreshInterval: 60_000 });

  const {
    data: logsData,
    error: logsError,
    isLoading: logsLoading,
    mutate: mutateLogs
  } = useSWR<LogsResponse>(activeView === 'logs' ? `${API_BASE_URL}/logs` : null, fetcher, {
    refreshInterval: 60_000,
    revalidateOnFocus: false
  });

  const {
    data: queueStatus,
    error: queueError,
    isLoading: queueLoading
  } = useSWR<QueueStatusResponse>(`${API_BASE_URL}/queue`, fetcher, {
    refreshInterval: 5_000,
    revalidateOnFocus: false
  });

  const repositories = repositoriesData?.repositories ?? [];
  const { selectedRepo, selectRepo, selectById } = useRepositorySelection(repositories);

  const logs = logsData?.logs ?? [];

  const [selectedDate, setSelectedDate] = React.useState<string | null>(null);
  const [showCreateForm, setShowCreateForm] = React.useState(false);
  const [newRepoUrl, setNewRepoUrl] = React.useState('');
  const [isCreating, setIsCreating] = React.useState(false);
  const [updatingRepoId, setUpdatingRepoId] = React.useState<string | null>(null);
  const [selectedLogId, setSelectedLogId] = React.useState<string | null>(null);
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

  React.useEffect(() => {
    if (activeView !== 'logs') {
      return;
    }

    if (!logs.length) {
      setSelectedLogId(null);
      return;
    }

    setSelectedLogId((current) => {
      if (current && logs.some((log) => log.id === current)) {
        return current;
      }
      return logs[0].id;
    });
  }, [activeView, logs]);

  const repoHistoryKey = React.useMemo(() => {
    if (!selectedRepo) {
      return null;
    }
    return `${API_BASE_URL}/repos/${encodeURIComponent(selectedRepo.organization)}/${encodeURIComponent(selectedRepo.repository)}/history`;
  }, [selectedRepo]);

  const selectedLog = React.useMemo(() => {
    if (!selectedLogId) {
      return null;
    }
    return logs.find((log) => log.id === selectedLogId) ?? null;
  }, [logs, selectedLogId]);

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

  const {
    content: logContent,
    isFetching: isLogFetching,
    error: logError,
    reload: reloadLog,
    lastUpdatedAt: logLastUpdatedAt,
    hasContent: logHasContent
  } = useLogStream(selectedLogId, { enabled: activeView === 'logs' });

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
        const expectedDate = extractDateFromFilename(result.output_filename);

        await waitForSummaryAvailability({
          organization: repo.organization,
          repository: repo.repository,
          expectedDate
        });

        await mutateRepositories();

        if (selectedRepo && formatRepositoryId(selectedRepo.organization, selectedRepo.repository) === repoId) {
          setSelectedDate(null);
          await Promise.all([mutateHistory(), mutateSummary()]);
        }

        const messageSuffix = result.output_filename ? ` (${result.output_filename})` : '';
        setStatusMessage({ type: 'success', text: `Summary generated for ${repoId}${messageSuffix}.` });
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
      const expectedDate = extractDateFromFilename(result.output_filename);

      await waitForSummaryAvailability({
        organization: result.repository.organization,
        repository: result.repository.repository,
        expectedDate
      });

      await mutateRepositories();

      if (repoHistoryKey) {
        await mutateHistory();
      }

      if (summaryKey) {
        await mutateSummary();
      }

      const messageSuffix = result.output_filename ? ` (${result.output_filename})` : '';
      setStatusMessage({ type: 'success', text: `Summary generated for ${repoId}${messageSuffix}.` });
      setNewRepoUrl('');
      setShowCreateForm(false);
      selectById(repoId);
      setSelectedDate(null);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to generate summary.';
      setStatusMessage({ type: 'error', text: message });
    } finally {
      setIsCreating(false);
    }
  }, [
    mutateHistory,
    mutateRepositories,
    mutateSummary,
    newRepoUrl,
    repoHistoryKey,
    selectById,
    summaryKey,
    triggerGeneration
  ]);

  const isReady = !repositoriesLoading && !summaryLoading;

  return (
    <main className="flex min-h-screen flex-col bg-background text-foreground">
      <header className="flex items-center justify-between border-b px-8 py-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">GitHub Repository Update Viewer</h1>
          <p className="text-sm text-muted-foreground">Browse curated Markdown summaries across your favorite repositories.</p>
        </div>
        <div className="flex items-center gap-2">
          <QueueStatusMenu status={queueStatus} isLoading={queueLoading} error={queueError} />
          <ThemeToggle />
          <SettingsMenu activeView={activeView} onSelectView={setActiveView} />
        </div>
      </header>

      {activeView === 'summaries' ? (
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
                <Plus className="h-4 w-4" aria-hidden="true" />
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
              size="icon"
              disabled={!selectedRepo || isSelectedRepoUpdating}
              aria-label={isSelectedRepoUpdating ? 'Generating latest summary' : 'Generate latest summary'}
              onClick={() => {
                if (selectedRepo) {
                  handleUpdateRepository(selectedRepo);
                }
              }}
            >
              {isSelectedRepoUpdating ? (
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
              ) : (
                <RefreshCcw className="h-4 w-4" aria-hidden="true" />
              )}
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
      ) : (
        <div className="flex flex-1 flex-col gap-6 px-8 pb-8 pt-6 lg:flex-row">
          <Card className="w-full flex-none lg:w-72">
            <CardHeader>
              <CardTitle className="text-lg">Log Files</CardTitle>
              <CardDescription>Select a log to monitor streaming updates.</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4 pt-2">
              {logsLoading && <Skeleton className="h-10 w-full" />}
              {logsError && <p className="text-sm text-destructive">Failed to load log files. Please try again.</p>}

              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Logs</span>
                <Button
                  type="button"
                  variant="outline"
                  size="icon"
                  aria-label="Refresh log list"
                  disabled={logsLoading}
                  onClick={() => mutateLogs?.(undefined, { revalidate: true })}
                >
                  {logsLoading ? (
                    <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                  ) : (
                    <RefreshCcw className="h-4 w-4" aria-hidden="true" />
                  )}
                </Button>
              </div>

              <ScrollArea className="h-[60vh]">
                <div className="flex flex-col gap-2">
                  {logs.map((log) => {
                    const isActive = selectedLogId === log.id;
                    return (
                      <button
                        key={log.id}
                        type="button"
                        className={cn(
                          'flex w-full items-start gap-2 rounded-md border px-3 py-2 text-left transition hover:border-accent hover:bg-accent',
                          isActive ? 'border-primary bg-primary/10 text-primary-foreground dark:bg-primary/20' : 'border-border'
                        )}
                        onClick={() => setSelectedLogId(log.id)}
                      >
                        <FileText className="mt-0.5 h-4 w-4 flex-none text-muted-foreground" aria-hidden="true" />
                        <div className="flex flex-1 flex-col">
                          <span className="text-sm font-medium">{log.name}</span>
                          <span className="text-xs text-muted-foreground">
                            {formatFileSize(log.size)} • Updated {formatDateTime(log.mtime)}
                          </span>
                        </div>
                      </button>
                    );
                  })}

                  {!logsLoading && !logsError && logs.length === 0 && (
                    <p className="text-sm text-muted-foreground">No log files were found. Add logs to the server to monitor activity.</p>
                  )}
                </div>
              </ScrollArea>
            </CardContent>
          </Card>

          <Card className="flex-1">
            <CardHeader className="flex flex-row items-start justify-between space-y-0">
              <div>
                <CardTitle className="text-lg">{selectedLog ? selectedLog.name : 'Select a log file'}</CardTitle>
                <CardDescription>
                  {selectedLog
                    ? `${formatFileSize(selectedLog.size)} • Modified ${formatDateTime(selectedLog.mtime)}`
                    : 'Choose a log to begin streaming output.'}
                </CardDescription>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-xs text-muted-foreground">{formatLastUpdated(logLastUpdatedAt)}</span>
                <Button
                  type="button"
                  variant="outline"
                  size="icon"
                  disabled={!selectedLogId || isLogFetching}
                  aria-label="Reload log contents"
                  onClick={() => {
                    reloadLog();
                    mutateLogs?.(undefined, { revalidate: true });
                  }}
                >
                  {isLogFetching ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <RefreshCcw className="h-4 w-4" aria-hidden="true" />}
                </Button>
              </div>
            </CardHeader>
            <CardContent className="pt-0">
              {logError && (
                <p className="mb-3 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {logError.message}
                </p>
              )}
              <div className="rounded-md border bg-muted/10">
                <ScrollArea className="h-[60vh]" viewportClassName="pr-3">
                  <pre className="whitespace-pre-wrap px-4 py-3 font-mono text-sm leading-relaxed">
                    {logContent}
                    {!logError && !logHasContent && !isLogFetching && (
                      <span className="text-muted-foreground">
                        {selectedLogId ? 'Log output will appear here once data is available.' : 'Select a log file to begin monitoring output.'}
                      </span>
                    )}
                    {isLogFetching && !logHasContent && (
                      <span className="text-muted-foreground">Loading log data…</span>
                    )}
                  </pre>
                </ScrollArea>
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </main>
  );
}
