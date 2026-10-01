# Stale partial blobs: told apart by mtime against refs/main

`is_downloaded` in `lib/download.sh` treats a partial blob (`blobs/*.incomplete`) that no snapshot symlink points to as part of the current revision when it is at least as new as `refs/main`, and as a stale leftover when it is older. A partial blob for a file the revision links to always counts. Both the `<blob>.<uuid8>.incomplete` name of hf 2.0.0 and the older `<blob>.incomplete` match.

This relies on how `huggingface_hub` 2.0.0 downloads (`file_download.py`):

- It writes `refs/main` before it fetches any file, atomically and only when the commit changes. Its mtime is the time the current revision first arrived.
- It deletes the temp file in a `finally` block, so an exception or Ctrl-C leaves none behind.

## Considered options

- Check the hf lock files (`.locks/models--<repo>/<etag>.lock`) for a download in progress: hf calls the lock best-effort and says cache correctness does not depend on it, and lock files stay after release.

## Consequences

- Copying the cache, or restoring it from a backup, can change timestamps and misclassify a partial blob.
- Clock skew between writers of the cache can do the same.
- A download that is hard-killed (SIGKILL, OOM kill, power loss) leaves a partial blob. If it is at least as new as `refs/main`, the Download stays incomplete until the file is fetched again or the leftover is deleted.
- A non-shard file that was never fetched leaves no link and no partial blob, so it isn't detected.
