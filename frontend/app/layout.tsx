import type { Metadata } from 'next';

import './globals.css';

import { ThemeProvider } from '@/components/theme-provider';
import { cn } from '@/lib/utils';

export const metadata: Metadata = {
  title: 'GitHub Repository Update Viewer',
  description: 'A sleek viewer for GitHub repository update summaries.'
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={cn('min-h-screen bg-background font-sans antialiased')}>
        <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
          {children}
        </ThemeProvider>
      </body>
    </html>
  );
}
