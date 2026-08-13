/** Tiny round photo or initial — profile `avatar_url` or handle fallback. */
export function ContactAvatar({
  handle,
  avatarUrl,
  name,
  size = 36,
}: {
  handle: string;
  avatarUrl?: string;
  name?: string;
  size?: number;
}) {
  const initial = (name?.trim() || handle.split("@")[0] || "?")
    .charAt(0)
    .toUpperCase();
  const dim = `${size}px`;

  if (avatarUrl) {
    return (
      // eslint-disable-next-line @next/next/no-img-element -- data URLs / hub https
      <img
        src={avatarUrl}
        alt=""
        width={size}
        height={size}
        className="shrink-0 rounded-full object-cover ring-1 ring-stone-900/10"
        style={{ width: dim, height: dim }}
      />
    );
  }

  return (
    <span
      aria-hidden
      className="inline-flex shrink-0 items-center justify-center rounded-full bg-stone-200 font-semibold uppercase text-stone-600 ring-1 ring-stone-900/10"
      style={{ width: dim, height: dim, fontSize: Math.max(11, size * 0.38) }}
    >
      {initial}
    </span>
  );
}
