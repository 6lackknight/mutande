import Image from "next/image";
import Link from "next/link";
import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from "react";

export function Shell({
  children,
  wide,
}: {
  children: ReactNode;
  wide?: boolean;
}) {
  return (
    <div className="bg-relay grain relative min-h-full flex-1">
      <div
        className={`relative mx-auto w-full px-6 py-10 sm:px-8 ${wide ? "max-w-3xl" : "max-w-lg"}`}
      >
        {children}
      </div>
    </div>
  );
}

export function BrandMark({
  className = "",
  size = "md",
}: {
  className?: string;
  size?: "sm" | "md" | "lg";
}) {
  const icon = size === "lg" ? 40 : size === "sm" ? 22 : 28;
  const text =
    size === "lg"
      ? "text-2xl"
      : size === "sm"
        ? "text-base"
        : "text-xl";

  return (
    <Link
      href="/"
      className={`inline-flex items-center gap-2.5 font-display font-semibold tracking-tight text-stone-900 ${text} ${className}`}
    >
      <Image
        src="/brand/tray-icon.png"
        alt=""
        width={icon}
        height={icon}
        className="rounded-[22%] shadow-sm"
        priority
      />
      <span>mutande</span>
    </Link>
  );
}

export function PageTitle({
  title,
  subtitle,
}: {
  title: string;
  subtitle?: string;
}) {
  return (
    <header className="mb-8">
      <h1 className="font-display text-3xl font-semibold tracking-tight text-stone-900 sm:text-4xl">
        {title}
      </h1>
      {subtitle ? (
        <p className="mt-2 max-w-prose text-[15px] leading-relaxed text-muted">
          {subtitle}
        </p>
      ) : null}
    </header>
  );
}

export function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <label className="block space-y-1.5">
      <span className="text-[13px] font-medium tracking-wide text-stone-700">
        {label}
      </span>
      {children}
      {hint ? <span className="block text-xs text-muted">{hint}</span> : null}
    </label>
  );
}

export function Input(props: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={`w-full rounded-md border border-stone-300/80 bg-white/70 px-3 py-2.5 text-[15px] text-foreground outline-none transition placeholder:text-stone-300 focus:border-accent focus:ring-2 focus:ring-accent/20 ${props.className ?? ""}`}
    />
  );
}

const buttonStyles = {
  primary: "bg-stone-900 text-stone-50 hover:bg-stone-800",
  secondary:
    "border border-stone-300/90 bg-white/60 text-stone-800 hover:bg-white",
  ghost: "text-stone-700 hover:bg-stone-200/50",
} as const;

export function buttonClass(
  variant: keyof typeof buttonStyles = "primary",
  className = "",
): string {
  return `inline-flex items-center justify-center rounded-md px-4 py-2.5 text-[14px] font-medium transition disabled:cursor-not-allowed disabled:opacity-50 ${buttonStyles[variant]} ${className}`;
}

export function Button({
  variant = "primary",
  className = "",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: keyof typeof buttonStyles;
}) {
  return <button {...props} className={buttonClass(variant, className)} />;
}

export function ButtonLink({
  href,
  variant = "primary",
  className = "",
  children,
}: {
  href: string;
  variant?: keyof typeof buttonStyles;
  className?: string;
  children: ReactNode;
}) {
  return (
    <a href={href} className={buttonClass(variant, className)}>
      {children}
    </a>
  );
}

export function Alert({
  children,
  tone = "amber",
}: {
  children: ReactNode;
  tone?: "amber" | "ok" | "danger";
}) {
  const toneClass =
    tone === "ok"
      ? "border-accent/30 bg-accent-soft text-stone-800"
      : tone === "danger"
        ? "border-red-300/60 bg-red-50 text-red-900"
        : "border-amber-300/50 bg-amber-50/80 text-stone-800";

  return (
    <div
      role="status"
      className={`rounded-md border px-3 py-2.5 text-sm leading-relaxed ${toneClass}`}
    >
      {children}
    </div>
  );
}

export function ChoiceCard({
  href,
  title,
  description,
}: {
  href: string;
  title: string;
  description: string;
}) {
  return (
    <a
      href={href}
      className="group block rounded-lg border border-stone-300/70 bg-white/50 p-5 transition hover:border-stone-400 hover:bg-white/80"
    >
      <div className="font-display text-lg text-stone-900 group-hover:text-stone-800">
        {title}
      </div>
      <p className="mt-1.5 text-sm leading-relaxed text-muted">{description}</p>
    </a>
  );
}
