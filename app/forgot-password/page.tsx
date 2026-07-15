import { ForgotPasswordForm } from "./forgot-password-form";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Forgot password — UZURI Intelligence Platform",
};

export default function ForgotPasswordPage() {
  return (
    <main className="mx-auto max-w-sm p-8 font-sans">
      <h1 className="text-xl font-semibold">Forgot password</h1>
      <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
        Enter your email and we&apos;ll send you a link to reset your password.
      </p>
      <ForgotPasswordForm />
    </main>
  );
}
