"use client";

import { useActionState, useRef, useState } from "react";
import { updateProfileAction, type ActionState } from "@/app/actions";
import { Alert, Button, Field, Input } from "@/components/ui";

const initial: ActionState = {};

/** Client-side resize keeps avatars tiny (hub stores them inline in KV). */
const AVATAR_SIZE = 192;

async function fileToAvatarDataUrl(file: File): Promise<string> {
  const bitmap = await createImageBitmap(file);
  const side = Math.min(bitmap.width, bitmap.height);
  const canvas = document.createElement("canvas");
  canvas.width = AVATAR_SIZE;
  canvas.height = AVATAR_SIZE;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Canvas unavailable");
  ctx.imageSmoothingQuality = "high";
  // Center-crop to square, then downscale.
  ctx.drawImage(
    bitmap,
    (bitmap.width - side) / 2,
    (bitmap.height - side) / 2,
    side,
    side,
    0,
    0,
    AVATAR_SIZE,
    AVATAR_SIZE,
  );
  bitmap.close();
  return canvas.toDataURL("image/jpeg", 0.85);
}

function Avatar({ src, fallback }: { src: string | null; fallback: string }) {
  if (src) {
    // eslint-disable-next-line @next/next/no-img-element -- data URLs don't need next/image
    return (
      <img
        src={src}
        alt="Avatar"
        className="h-20 w-20 rounded-full object-cover ring-1 ring-stone-900/10"
      />
    );
  }
  return (
    <div className="flex h-20 w-20 items-center justify-center rounded-full bg-stone-200 font-display text-2xl font-semibold uppercase text-stone-600 ring-1 ring-stone-900/10">
      {fallback}
    </div>
  );
}

function splitHandle(handle: string): { local: string; orgSlug: string } {
  const at = handle.lastIndexOf("@");
  if (at <= 0) return { local: handle, orgSlug: "" };
  return { local: handle.slice(0, at), orgSlug: handle.slice(at + 1) };
}

export function ProfileForm({
  initialName,
  initialAvatarUrl,
  handle,
  email,
}: {
  initialName: string;
  initialAvatarUrl: string | null;
  handle: string;
  email: string;
}) {
  const [state, action, pending] = useActionState(updateProfileAction, initial);
  const [avatar, setAvatar] = useState<string | null>(initialAvatarUrl);
  const [avatarChanged, setAvatarChanged] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const { local, orgSlug } = splitHandle(handle);

  const fallbackInitial = (initialName || handle || email || "?")
    .trim()
    .charAt(0);

  const onPickFile = async (file: File | undefined) => {
    if (!file) return;
    setAvatarError(null);
    try {
      const dataUrl = await fileToAvatarDataUrl(file);
      setAvatar(dataUrl);
      setAvatarChanged(true);
    } catch {
      setAvatarError("Couldn't read that image — try a PNG or JPEG.");
    }
  };

  return (
    <form action={action} className="space-y-6">
      {state.error ? <Alert tone="danger">{state.error}</Alert> : null}
      {state.ok && !pending ? <Alert tone="ok">{state.ok}</Alert> : null}
      {avatarError ? <Alert tone="danger">{avatarError}</Alert> : null}

      <div className="flex items-center gap-5">
        <Avatar src={avatar} fallback={fallbackInitial} />
        <div className="flex flex-wrap items-center gap-2">
          <Button
            type="button"
            variant="secondary"
            onClick={() => fileRef.current?.click()}
          >
            {avatar ? "Change photo" : "Upload photo"}
          </Button>
          {avatar ? (
            <Button
              type="button"
              variant="ghost"
              onClick={() => {
                setAvatar(null);
                setAvatarChanged(true);
                if (fileRef.current) fileRef.current.value = "";
              }}
            >
              Remove
            </Button>
          ) : null}
        </div>
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => onPickFile(e.target.files?.[0])}
        />
        {avatarChanged ? (
          <input type="hidden" name="avatar_url" value={avatar ?? ""} />
        ) : null}
      </div>

      <Field label="Name" hint="Shown to teammates alongside your handle.">
        <Input
          name="display_name"
          defaultValue={initialName}
          maxLength={128}
          autoComplete="name"
          placeholder="Your name"
        />
      </Field>

      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          label="Handle"
          hint={
            orgSlug
              ? "Local part only — org stays fixed. Old mail keeps the previous address."
              : "Lowercase letters, digits, dots, underscores, or hyphens."
          }
        >
          <div className="flex items-center gap-1.5">
            <Input
              name="handle_local"
              defaultValue={local}
              required
              autoComplete="off"
              spellCheck={false}
              maxLength={32}
              className="min-w-0 flex-1"
              pattern="[a-z0-9]([a-z0-9._-]{0,30}[a-z0-9])?"
              title="1–32 lowercase letters, digits, dots, underscores, or hyphens"
            />
            {orgSlug ? (
              <span className="shrink-0 text-[15px] text-stone-500">
                @{orgSlug}
              </span>
            ) : null}
          </div>
        </Field>
        <div>
          <div className="text-[13px] font-medium tracking-wide text-stone-700">
            Email
          </div>
          <div className="mt-1.5 text-[15px] text-stone-500">{email}</div>
        </div>
      </div>

      <Button type="submit" disabled={pending}>
        {pending ? "Saving…" : "Save profile"}
      </Button>
    </form>
  );
}
