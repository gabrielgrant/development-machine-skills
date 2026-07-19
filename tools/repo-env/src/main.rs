//! repo-env: personal per-repo dev environments for repos you don't control.
//!
//! Maps a checkout's `origin` remote to an overlay directory under
//! `$SERVER_CONFIG_DIR/environments/<host>/<owner>/<repo>/`, keeps a
//! git-ignored `.envrc` in the checkout pointing at it, and wraps
//! `direnv exec` so agents and non-interactive launches get the environment.

use std::env;
use std::fs;
use std::io::Write as _;
use std::path::PathBuf;
use std::process::{exit, Command};

const USAGE: &str = "\
repo-env — personal per-repo dev environments

USAGE:
    repo-env key            print the overlay key for this checkout (host/owner/repo)
    repo-env path           print the overlay directory path
    repo-env init           create the overlay directory (with empty devbox.json) if missing
    repo-env setup          init + write git-ignored .envrc + direnv allow
    repo-env exec CMD...    run CMD inside the environment (direnv exec at the git root)
    repo-env doctor         check that all required pieces are in place

ENVIRONMENT:
    SERVER_CONFIG_DIR       config repo location (default: ~/server-config)
";

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("key") => cmd_key(),
        Some("path") => cmd_path(),
        Some("init") => cmd_init(),
        Some("setup") => cmd_setup(),
        Some("exec") => cmd_exec(&args[1..]),
        Some("doctor") => cmd_doctor(),
        Some("-h") | Some("--help") | None => {
            print!("{USAGE}");
            Ok(())
        }
        Some(other) => Err(format!("unknown subcommand: {other}\n\n{USAGE}")),
    };
    if let Err(e) = result {
        eprintln!("repo-env: {e}");
        exit(1);
    }
}

// --- helpers ---------------------------------------------------------------

fn git(args: &[&str]) -> Result<String, String> {
    let out = Command::new("git")
        .args(args)
        .output()
        .map_err(|e| format!("failed to run git: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn git_root() -> Result<PathBuf, String> {
    Ok(PathBuf::from(git(&["rev-parse", "--show-toplevel"])?))
}

fn home() -> PathBuf {
    PathBuf::from(env::var("HOME").expect("HOME not set"))
}

fn server_config_dir() -> PathBuf {
    env::var("SERVER_CONFIG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home().join("server-config"))
}

/// Normalize a git remote URL to `host/owner/repo`.
///
/// Handles: git@host:owner/repo(.git), ssh://git@host[:port]/owner/repo(.git),
/// https://host/owner/repo(.git), and nested groups (gitlab subgroups).
fn normalize_remote(url: &str) -> Result<String, String> {
    let url = url.trim();
    let stripped = if let Some(rest) = url.strip_prefix("ssh://") {
        // ssh://git@host[:port]/path
        let rest = rest.split_once('@').map(|(_, r)| r).unwrap_or(rest);
        let (host, path) = rest
            .split_once('/')
            .ok_or_else(|| format!("unparseable remote: {url}"))?;
        let host = host.split(':').next().unwrap_or(host);
        format!("{host}/{path}")
    } else if let Some(rest) = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))
        .or_else(|| url.strip_prefix("git://"))
    {
        let rest = rest.split_once('@').map(|(_, r)| r).unwrap_or(rest);
        rest.to_string()
    } else if let Some((userhost, path)) = url.split_once(':') {
        // scp-like: git@host:owner/repo
        let host = userhost.split_once('@').map(|(_, h)| h).unwrap_or(userhost);
        format!("{host}/{path}")
    } else {
        return Err(format!("unparseable remote: {url}"));
    };
    let key = stripped
        .trim_end_matches('/')
        .trim_end_matches(".git")
        .to_lowercase();
    if key.split('/').count() < 3 {
        return Err(format!("remote does not look like host/owner/repo: {url}"));
    }
    Ok(key)
}

/// Overlay key: `host/owner/repo` from the origin remote when present;
/// `local/<dirname>` for a git repo with no origin (new project not yet
/// pushed anywhere). Not being in a git repo at all is an error.
fn overlay_key() -> Result<String, String> {
    let root = git_root().map_err(|_| {
        "not inside a git repository — run `git init` first \
         (repo-env keys the overlay off the repo: origin remote when \
         present, directory name otherwise)"
            .to_string()
    })?;
    match git(&["remote", "get-url", "origin"]) {
        Ok(url) => normalize_remote(&url),
        Err(_) => {
            let name = root
                .file_name()
                .and_then(|n| n.to_str())
                .ok_or_else(|| format!("cannot derive a name from {}", root.display()))?
                .to_lowercase();
            eprintln!(
                "note: no origin remote; using local overlay key `local/{name}`. \
                 When you add an origin, `repo-env doctor` will flag the mismatch \
                 and you can move the overlay dir."
            );
            Ok(format!("local/{name}"))
        }
    }
}

fn overlay_dir() -> Result<PathBuf, String> {
    Ok(server_config_dir().join("environments").join(overlay_key()?))
}

fn run_status(cmd: &str, args: &[&str]) -> Result<(), String> {
    let status = Command::new(cmd)
        .args(args)
        .status()
        .map_err(|e| format!("failed to run {cmd}: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{cmd} {} failed", args.join(" ")))
    }
}

fn have(cmd: &str) -> bool {
    env::var_os("PATH")
        .map(|paths| {
            env::split_paths(&paths).any(|dir| {
                let p = dir.join(cmd);
                p.is_file() || p.is_symlink()
            })
        })
        .unwrap_or(false)
}

// --- subcommands ------------------------------------------------------------

fn cmd_key() -> Result<(), String> {
    println!("{}", overlay_key()?);
    Ok(())
}

fn cmd_path() -> Result<(), String> {
    println!("{}", overlay_dir()?.display());
    Ok(())
}

fn cmd_init() -> Result<(), String> {
    let dir = overlay_dir()?;
    fs::create_dir_all(&dir).map_err(|e| format!("mkdir {}: {e}", dir.display()))?;
    let devbox = dir.join("devbox.json");
    if !devbox.exists() {
        fs::write(&devbox, "{\n  \"packages\": []\n}\n")
            .map_err(|e| format!("write {}: {e}", devbox.display()))?;
        println!("created {}", devbox.display());
    } else {
        println!("exists  {}", devbox.display());
    }
    Ok(())
}

fn cmd_setup() -> Result<(), String> {
    cmd_init()?;
    let root = git_root()?;
    let key = overlay_key()?;

    // 1. .envrc (only if absent — never clobber a hand-edited one)
    let envrc = root.join(".envrc");
    if !envrc.exists() {
        let mut content = format!("use_personal_devbox {key}\n");
        if root.join(".nvmrc").exists() {
            content.push_str(
                "\n# Upstream .nvmrc is the Node authority here.\n\
                 export NVM_DIR=\"$HOME/.nvm\"\n\
                 if [ -s \"$NVM_DIR/nvm.sh\" ]; then\n\
                 \x20   . \"$NVM_DIR/nvm.sh\"\n\
                 \x20   nvm use --silent\n\
                 fi\n",
            );
        }
        fs::write(&envrc, content).map_err(|e| format!("write .envrc: {e}"))?;
        println!("created {}", envrc.display());
    } else {
        println!("exists  {}", envrc.display());
    }

    // 2. exclude .envrc locally (never touch upstream's .gitignore)
    let exclude = root.join(".git/info/exclude");
    let existing = fs::read_to_string(&exclude).unwrap_or_default();
    if !existing.lines().any(|l| l.trim() == "/.envrc") {
        if let Some(parent) = exclude.parent() {
            fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {e}", parent.display()))?;
        }
        let mut f = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&exclude)
            .map_err(|e| format!("open {}: {e}", exclude.display()))?;
        let sep = if existing.is_empty() || existing.ends_with('\n') { "" } else { "\n" };
        writeln!(f, "{sep}/.envrc").map_err(|e| format!("write exclude: {e}"))?;
        println!("excluded .envrc via .git/info/exclude");
    }

    // 3. direnv allow
    run_status("direnv", &["allow", root.to_str().unwrap_or(".")])?;
    println!("direnv allowed. cd into the repo (or `repo-env exec`) to activate.");
    Ok(())
}

fn cmd_exec(cmd: &[String]) -> Result<(), String> {
    if cmd.is_empty() {
        return Err("exec requires a command, e.g.: repo-env exec claude".into());
    }
    let root = git_root()?;
    let status = Command::new("direnv")
        .arg("exec")
        .arg(&root)
        .args(cmd)
        .status()
        .map_err(|e| format!("failed to run direnv: {e}"))?;
    exit(status.code().unwrap_or(1));
}

fn cmd_doctor() -> Result<(), String> {
    let mut ok = true;
    let mut check = |name: &str, pass: bool, hint: &str| {
        println!("{} {name}{}", if pass { "ok  " } else { "FAIL" },
                 if pass { String::new() } else { format!("  ({hint})") });
        ok &= pass;
    };

    check("direnv installed", have("direnv"), "apt install direnv");
    check("devbox installed", have("devbox"), "see setting-up-dev-machine skill");
    let helper = home().join(".config/direnv/lib/use_personal_devbox.sh");
    check(
        "use_personal_devbox helper",
        helper.exists(),
        "run setting-up-dev-machine bootstrap.sh",
    );
    let cfg = server_config_dir();
    check(
        "server-config dir",
        cfg.is_dir(),
        &format!("expected {}", cfg.display()),
    );

    match overlay_dir() {
        Ok(dir) => {
            let devbox_json = dir.join("devbox.json");
            check(
                "overlay for this repo",
                devbox_json.exists(),
                "run repo-env setup",
            );
            if let Ok(root) = git_root() {
                let envrc = root.join(".envrc");
                check(
                    ".envrc in checkout",
                    envrc.exists(),
                    "run repo-env setup",
                );
                // Stale key: .envrc written before an origin remote existed
                // (or the remote moved) no longer matches the derived key.
                if let (Ok(contents), Ok(key)) = (fs::read_to_string(&envrc), overlay_key()) {
                    let envrc_key = contents
                        .lines()
                        .find_map(|l| l.trim().strip_prefix("use_personal_devbox "))
                        .map(str::trim);
                    if let Some(ek) = envrc_key {
                        check(
                            ".envrc key matches repo",
                            ek == key,
                            &format!(
                                "envrc uses `{ek}`, repo now derives `{key}` — \
                                 move the overlay dir and rerun repo-env setup after \
                                 deleting .envrc"
                            ),
                        );
                    }
                }
            }
        }
        Err(e) => println!("note: not in a repo with an origin remote ({e})"),
    }

    if ok {
        Ok(())
    } else {
        Err("some checks failed".into())
    }
}

#[cfg(test)]
mod tests {
    use super::normalize_remote;

    #[test]
    fn normalizes_remote_forms() {
        for (input, want) in [
            ("git@github.com:Owner/Repo.git", "github.com/owner/repo"),
            ("https://github.com/owner/repo", "github.com/owner/repo"),
            ("https://user@github.com/owner/repo.git", "github.com/owner/repo"),
            ("ssh://git@gitlab.com:2222/group/sub/repo.git", "gitlab.com/group/sub/repo"),
            ("git://host.example/owner/repo.git", "host.example/owner/repo"),
        ] {
            assert_eq!(normalize_remote(input).unwrap(), want, "input: {input}");
        }
    }

    #[test]
    fn rejects_garbage() {
        assert!(normalize_remote("/local/path").is_err());
        assert!(normalize_remote("https://host/only-owner").is_err());
    }
}
