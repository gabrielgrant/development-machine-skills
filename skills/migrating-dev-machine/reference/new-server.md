# Old server → new server migration

Assumes same username/UID on both machines (check `id` on both; if they
differ, don't use `--numeric-ids` — fix ownership on the destination after).
`$MIG` below is a staging dir on the new server, e.g. `~/migration`.

## Contents
- Phase 1: Preserve and inventory
- Phase 2: Stage and compare
- Phase 3: Merge conflicts
- Phase 4: Rebuild the managed layers
- Phase 5: Cutover
- Phase 6: Decommission

## Phase 1: Preserve and inventory

1. Provider snapshots of both machines.
2. On the **new** server, before anything else, save the pristine home and skel:
   ```bash
   MIG="$HOME/migration"; mkdir -p "$MIG"/{new-home-pristine,new-skel,merged}; chmod 700 "$MIG"
   rsync -aHAXS --exclude='/migration/' "$HOME/" "$MIG/new-home-pristine/"
   sudo rsync -aHAXS /etc/skel/ "$MIG/new-skel/" && sudo chown -R "$USER:$USER" "$MIG"
   ```
3. On the **old** server: run `scripts/machine-inventory.sh` (it lands in the
   home dir, so it comes across with the copy).
4. Verify SSH new→old works before proceeding.

## Phase 2: Stage and compare

5. Stage old skel and home onto the new server (containers may still run;
   a final sync fixes drift later):
   ```bash
   OLD="user@old-ip"
   rsync -aHAXS --partial --info=progress2 "$OLD:/etc/skel/" "$MIG/old-skel/"
   rsync -aHAXS --partial --info=progress2 "$OLD:~/" "$MIG/old-home/"
   ```
   Keep caches — disk is cheap, rebuilds aren't; drop individual caches only
   if they misbehave on the new OS.
6. Run `scripts/home-conflicts.sh "$MIG/old-home"` — expect a short
   shared-differences list (shell files, `.ssh/*`).

## Phase 3: Merge conflicts

7. For each shared file with a meaningful base, three-way merge
   (current=new default, base=old default, other=your old file):
   ```bash
   git merge-file --diff3 -p \
     "$MIG/new-home-pristine/.bashrc" "$MIG/old-skel/.bashrc" "$MIG/old-home/.bashrc" \
     > "$MIG/merged/.bashrc" || true   # then resolve markers, review, install
   ```
   Shortcut: if old file == old skel, keep the new file; often the distro
   defaults are identical across releases and the "merge" is just deciding
   which old customizations to keep. Expect most old `.bashrc` lines to be
   installer-added — do NOT carry them over; reinstalling the tools
   (Phase 4) recreates what's needed as managed snippets
   (see normalizing-dotfiles).
8. Special files:
   - `authorized_keys`: `cat new old | awk 'NF && !seen[$0]++'` → review → install.
   - Private keys: keep the new machine's key under its name; bring old keys
     over under renamed files only if still needed; mode 600.
   - `.bash_history`: concatenate after all old-server shells have exited.
   - Binary conflicts: pick one or keep both under different names.

## Phase 4: Rebuild the managed layers

9. Copy everything non-conflicting into the live home (dry-run with `-n` first):
   ```bash
   rsync -aHAXSi --ignore-existing --omit-dir-times --exclude='/migration/' \
     "$MIG/old-home/" "$HOME/"
   ```
10. Now run the **setting-up-dev-machine** skill (etckeeper first). Move
    aside copied installer-managed dirs before reinstalling their tools
    (`mv ~/.rustup ~/.rustup.old` etc.), reinstall via
    **installing-dev-tools**, then restore useful caches/config from the
    copies.
11. APT: build an approved list from the old inventory's
    `apt-commandlines.txt` (the `Commandline:` entries are what you actually
    typed) minus provisioning noise (grub, qemu-guest-agent, unattended
    upgrades, cloud-image bundles). Check availability
    (`apt-cache show`), then add them to `host/apt-packages.txt` and rerun
    `host/apply.sh` — current versions, dependencies auto-resolved.
    Recreate holds only if you remember why.
12. System config: from `dpkg-conffile-changes.tsv` and
    `custom-system-paths.tsv`, reapply only deliberate customizations
    (systemd units, sshd_config.d, sysctl.d, cron). Validate sshd with
    `sudo sshd -t` and keep an existing session open while testing.

## Phase 5: Cutover

13. Test first: `systemctl --failed`, every repo's `git status`/`remote -v`,
    agent startup, builds, compose projects, second SSH session.
    Expect OAuth-based tools (claude, codex, sometimes gh) to demand one
    interactive re-login on the new machine even though their credential
    files transferred — refresh tokens are rotated server-side and a
    copied token pair is often rejected. Config/history/projects still
    carry over; a 401 on first use is normal, not a migration failure.
    Anything paired to the machine (e.g. `codex remote-control pair`)
    must be re-paired.
14. Stop old-server agents/containers/shells, then final sync into
    **staging** (safe to `--delete` there), re-run home-conflicts against
    the live home, and apply with a protect list:
    ```bash
    rsync -aHAXS --delete --partial "$OLD:~/" "$MIG/old-home/"
    printf '%s\n' /.bashrc /.profile /.bash_logout '/.ssh/authorized_keys' '/.ssh/id_*' \
      > "$MIG/protect.rsync"   # plus anything you resolved new-side
    rsync -aHAXSni --exclude-from="$MIG/protect.rsync" --exclude='/migration/' \
      "$MIG/old-home/" "$HOME/"          # inspect, then run without -n
    ```
    Never `--delete` into the live home.
15. Post-checks: `find ~ -xtype l` (broken symlinks, esp. absolute ones
    pointing at old paths), `.ssh` perms (700/600), `find ~ ! -user $USER`.

## Phase 6: Decommission

16. Power off the old VM but keep its disk/snapshot until the new machine
    has survived normal use and one complete backup cycle
    (see backing-up-dev-machine). Then delete, and remove stale DNS/SSH
    config entries pointing at it.
