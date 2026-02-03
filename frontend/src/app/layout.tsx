import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { Providers } from './providers';
import { Toaster } from 'sonner';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'Swarm Router | MEV-Protected DEX',
  description: 'Multi-agent trade router with MEV protection and LP fee optimization on Uniswap v4',
  keywords: ['DeFi', 'DEX', 'MEV Protection', 'Uniswap v4', 'Ethereum'],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <Providers>
          {children}
          <Toaster
            position="bottom-right"
            theme="dark"
            richColors
            closeButton
          />
        </Providers>
      </body>
    </html>
  );
}
