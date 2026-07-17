# In-place adoption (same machine)

Bring an existing, running machine under the managed pattern without
reinstalling the OS. Lower risk than a server move, but there is no fresh
baseline — the inventory substitutes for one.

1. **Snapshot** (provider-level if a VM), then run
   `scripts/machine-inventory.sh` and commit the result to
   `$SERVER_CONFIG_DIR/inventories/<host>-adoption/`.
2. **Bootstrap** via setting-up-dev-machine's `bootstrap.sh`. etckeeper's
   first commit becomes your `/etc` baseline — from now on package installs
   are recorded.
3. **Encode current APT state.** From `apt-commandlines.txt`, pick the
   packages you deliberately installed and declare them in the Ansible
   playbook. Run with `--check --diff` first; it should mostly report
   no changes — differences are drift to investigate.
4. **Adopt dotfiles gradually.** The loader block goes in via the modify_
   scripts without disturbing existing content. Then work through the
   existing installer-appended `.bashrc`/`.profile` lines with the
   normalizing-dotfiles skill: move each into a managed snippet or delete
   it. Done when the files are distro-default + loader block only.
5. **Adopt tools.** For each entry in `tool-locations.txt` /
   `user-bin.txt`, decide its layer with installing-dev-tools and record
   it (devbox global, overlay, flake, Ansible). Existing installs can stay
   as-is; the goal is that a rebuild would recreate them.
6. **Verify** with auditing-dev-machine: the audit should come back clean;
   anything it flags is state you haven't captured yet.
