import type { Metadata } from "next";
import "./globals.css";

// No next/font here on purpose — the real WeOwn brand loads zero webfonts
// (see .claude/skills/weownchat-design/SKILL.md). font-sans in globals.css
// is the exact system stack the dashboard and Keycloak theme both use.

export const metadata: Metadata = {
  title: "WeOwnChat — Answers from your own material, on your own server",
  description:
    "A dedicated AI assistant for agencies and professional practices. Your documents, your server, your clients' questions answered — public website chatbot and private team assistant in one product.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
