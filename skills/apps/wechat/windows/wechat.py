#!/usr/bin/env python3
"""
WeChat Tools - Unified CLI

Usage:
    wechat                              Check status
    wechat login                        Login new account
    wechat sync                         Decrypt latest databases
    wechat account                      List all accounts
    wechat search <query>               Search messages (all accounts)
    wechat search --account <name> <q>  Search in specific account
    wechat search --chats               List all chats
    wechat search --chats --account <n> List chats in specific account

Auto-flow: check → login (if needed) → sync
"""

import ctypes
import subprocess
import time
import json
import sys
import os
import sqlite3
from pathlib import Path
from datetime import datetime

# Fix Windows console encoding for Chinese/emoji
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

try:
    import winreg
    HAS_WINREG = True
except ImportError:
    HAS_WINREG = False

try:
    import zstandard as zstd
    HAS_ZSTD = True
except ImportError:
    HAS_ZSTD = False

# Paths
SCRIPT_DIR = Path(__file__).parent
DLL_PATH = SCRIPT_DIR / "bin" / "wx_key.dll"
DUMP_EXE = SCRIPT_DIR / "bin" / "wechat-dump-rs.exe"

# Data directory - platform-specific, configurable via WECHAT_DATA env var
# Windows: E:/wechat-data (local)
# Mac: SMB mount via Tailscale (smb://asus-wsl-ubuntu/edrive)
def get_data_dir():
    # 1. Check environment variable
    if os.environ.get('WECHAT_DATA'):
        return Path(os.environ['WECHAT_DATA'])
    # 2. Platform defaults
    if sys.platform == 'win32':
        return Path('E:/wechat-data')
    elif sys.platform == 'darwin':
        # SMB mount via Tailscale: smb://asus-wsl-ubuntu/edrive
        return Path('/Volumes/edrive/wechat-data')
    else:
        return SCRIPT_DIR / 'decrypted'

OUTPUT_DIR = get_data_dir()
CONFIG_PATH = OUTPUT_DIR / "wechat_config.json"  # Shared across platforms


# ============================================================
# Config Management (Multi-account support)
# ============================================================

def load_config():
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
                config = json.load(f)

            # Migrate old format to multi-account
            if 'key' in config and 'accounts' not in config:
                acc = config.get('account', 'default')
                config = {
                    'accounts': {
                        acc: {
                            'key': config['key'],
                            'extracted_at': config.get('extracted_at'),
                            'last_sync': config.get('last_sync')
                        }
                    },
                    'active': acc
                }
            return config
        except:
            pass
    return {'accounts': {}, 'active': None}


def save_config(config):
    # Ensure structure
    if 'accounts' not in config:
        # Migrate old format
        if 'key' in config:
            acc = config.get('account', 'default')
            config = {
                'accounts': {
                    acc: {
                        'key': config['key'],
                        'extracted_at': config.get('extracted_at'),
                        'last_sync': config.get('last_sync')
                    }
                },
                'active': acc
            }
    with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)


def get_active_account(config):
    """Get active account config"""
    active = config.get('active')
    if active and active in config.get('accounts', {}):
        return active, config['accounts'][active]
    # Return first account if no active
    accounts = config.get('accounts', {})
    if accounts:
        first = list(accounts.keys())[0]
        return first, accounts[first]
    return None, {}


def set_account_key(config, account, key):
    """Set key for an account"""
    if 'accounts' not in config:
        config['accounts'] = {}
    if account not in config['accounts']:
        config['accounts'][account] = {}
    config['accounts'][account]['key'] = key
    config['accounts'][account]['extracted_at'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    config['active'] = account
    return config


# ============================================================
# WeChat Detection
# ============================================================

def find_wechat_exe():
    """Find WeChat executable from registry"""
    if not HAS_WINREG:
        return None
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Tencent\Weixin")
        install_path, _ = winreg.QueryValueEx(key, "InstallPath")
        winreg.CloseKey(key)
        exe_path = Path(install_path) / "Weixin.exe"
        if exe_path.exists():
            return exe_path
    except:
        pass

    # Fallback paths
    for p in [
        Path(r"C:\Program Files\Tencent\Weixin\Weixin.exe"),
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Tencent" / "Weixin" / "Weixin.exe",
    ]:
        if p.exists():
            return p
    return None


def find_wechat_data_dir():
    """Find WeChat data directory"""
    base = Path(os.environ.get("USERPROFILE", "")) / "xwechat_files"
    if base.exists():
        return base
    return None


def get_wechat_pid():
    """Get running WeChat PID"""
    result = subprocess.run(
        ['tasklist', '/FI', 'IMAGENAME eq Weixin.exe', '/FO', 'CSV', '/NH'],
        capture_output=True, text=True
    )
    for line in result.stdout.strip().split('\n'):
        if 'Weixin.exe' in line:
            parts = line.replace('"', '').split(',')
            if len(parts) >= 2:
                return int(parts[1])
    return None


def get_accounts():
    """Get WeChat accounts from data directory"""
    data_dir = find_wechat_data_dir()
    if not data_dir:
        return []

    accounts = []
    for d in data_dir.iterdir():
        if d.is_dir() and d.name.startswith('wxid_'):
            db_dir = d / "db_storage" / "message"
            if db_dir.exists():
                accounts.append({
                    'wxid': d.name.rsplit('_', 1)[0],
                    'folder': d.name,
                    'db_dir': db_dir
                })
    return accounts


def find_databases(account_folder=None):
    """Find WeChat database files"""
    data_dir = find_wechat_data_dir()
    if not data_dir:
        return []

    dbs = []
    for acc_dir in data_dir.iterdir():
        if not acc_dir.is_dir():
            continue
        if account_folder and acc_dir.name != account_folder:
            continue

        db_dir = acc_dir / "db_storage" / "message"
        if db_dir.exists():
            for db_file in db_dir.glob("*.db"):
                if db_file.name.endswith('-shm') or db_file.name.endswith('-wal'):
                    continue
                dbs.append({
                    'path': db_file,
                    'account': acc_dir.name,
                    'name': db_file.name,
                    'size': db_file.stat().st_size
                })
    return dbs


# ============================================================
# Key Validation
# ============================================================

def validate_key(key, account_folder=None):
    """Check if key can decrypt databases"""
    if not key or len(key) != 64:
        return False, "Invalid key format"

    dbs = find_databases(account_folder)
    if not dbs:
        return False, "No databases found"

    # Try to decrypt a small database
    test_db = min(dbs, key=lambda x: x['size'])
    test_output = SCRIPT_DIR / ".test_decrypt.db"

    try:
        result = subprocess.run(
            [str(DUMP_EXE), '-k', key, '-f', str(test_db['path']), '-o', str(test_output), '--vv', '4'],
            capture_output=True, text=True, timeout=30
        )

        if test_output.exists():
            # Verify it's a valid SQLite database
            try:
                conn = sqlite3.connect(str(test_output))
                conn.execute("SELECT count(*) FROM sqlite_master")
                conn.close()
                test_output.unlink()
                return True, test_db['account']
            except:
                test_output.unlink()
                return False, "Decryption produced invalid database"
        else:
            return False, "Decryption failed"
    except subprocess.TimeoutExpired:
        return False, "Decryption timeout"
    except Exception as e:
        return False, str(e)


# ============================================================
# Key Extraction
# ============================================================

def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False


def run_as_admin():
    """Re-launch with admin privileges"""
    python_exe = sys.executable
    script_path = os.path.abspath(__file__)
    args = ' '.join(sys.argv[1:])
    try:
        result = ctypes.windll.shell32.ShellExecuteW(
            None, "runas", python_exe, f'"{script_path}" {args}', None, 1
        )
        return result > 32
    except:
        return False


def extract_key():
    """Extract key from running WeChat"""
    if not is_admin():
        print("[!] Admin required for key extraction")
        print("    Requesting elevation...")
        if run_as_admin():
            sys.exit(0)
        else:
            print("[!] Failed to get admin. Run as Administrator.")
            return None

    if not DLL_PATH.exists():
        print(f"[!] DLL not found: {DLL_PATH}")
        return None

    wechat_exe = find_wechat_exe()
    if not wechat_exe:
        print("[!] WeChat not found")
        return None

    # Kill existing WeChat
    print("[*] Closing WeChat...")
    for proc in ['Weixin.exe', 'WeChatAppEx.exe']:
        subprocess.run(['taskkill', '/F', '/IM', proc], capture_output=True)
    time.sleep(2)

    # Load DLL
    print("[*] Loading extraction module...")
    try:
        dll = ctypes.WinDLL(str(DLL_PATH))
        dll.InitializeHook.argtypes = [ctypes.c_uint32]
        dll.InitializeHook.restype = ctypes.c_bool
        dll.PollKeyData.argtypes = [ctypes.c_char_p, ctypes.c_int]
        dll.PollKeyData.restype = ctypes.c_bool
        dll.GetLastErrorMsg.argtypes = []
        dll.GetLastErrorMsg.restype = ctypes.c_char_p
        dll.CleanupHook.argtypes = []
        dll.CleanupHook.restype = None
    except Exception as e:
        print(f"[!] Failed to load DLL: {e}")
        return None

    # Start WeChat
    print("[*] Starting WeChat...")
    subprocess.Popen([str(wechat_exe)])

    # Wait for process
    print("[*] Waiting for WeChat to start...")
    pid = None
    for _ in range(30):
        pid = get_wechat_pid()
        if pid:
            break
        time.sleep(1)

    if not pid:
        print("[!] WeChat did not start")
        return None

    print(f"[*] Found WeChat (PID: {pid})")
    time.sleep(3)

    # Initialize hook
    print("[*] Initializing hook...")
    success = dll.InitializeHook(ctypes.c_uint32(pid))

    if not success:
        err = dll.GetLastErrorMsg()
        if err:
            print(f"[!] Hook failed: {err.decode('utf-8', errors='ignore')}")
        dll.CleanupHook()
        return None

    # Wait for key
    print()
    print("=" * 50)
    print("  >>> LOGIN TO WECHAT NOW <<<")
    print("=" * 50)
    print()

    key = None
    start = time.time()
    while time.time() - start < 120:
        buf = ctypes.create_string_buffer(128)
        if dll.PollKeyData(buf, 128):
            k = buf.value.decode('utf-8', errors='ignore')
            if k and len(k) == 64 and all(c in '0123456789abcdefABCDEF' for c in k):
                key = k.lower()
                break

        elapsed = int(time.time() - start)
        if elapsed % 15 == 0 and elapsed > 0:
            print(f"    Waiting... {120 - elapsed}s remaining")
        time.sleep(0.1)

    # Cleanup
    dll.CleanupHook()

    if key:
        print()
        print(f"[+] Key extracted: {key[:16]}...{key[-8:]}")

        # Find which account this key unlocks
        accounts = get_accounts()
        config = load_config()
        matched_account = None

        if accounts:
            # Filter: only test accounts without a valid key
            unassigned = []
            for acc in accounts:
                existing_key = config.get('accounts', {}).get(acc['folder'], {}).get('key')
                if existing_key:
                    # Already has a key - skip unless it's the same key
                    if existing_key == key:
                        matched_account = acc['folder']
                        print(f"[+] Key already assigned to: {matched_account}")
                        break
                else:
                    unassigned.append(acc)

            if not matched_account and unassigned:
                print(f"[*] Testing {len(unassigned)} unassigned account(s)...")

                # Test in parallel using ThreadPoolExecutor
                from concurrent.futures import ThreadPoolExecutor, as_completed

                def test_account(acc):
                    valid, _ = validate_key(key, acc['folder'])
                    return acc['folder'] if valid else None

                with ThreadPoolExecutor(max_workers=len(unassigned)) as executor:
                    futures = {executor.submit(test_account, acc): acc for acc in unassigned}
                    for future in as_completed(futures):
                        result = future.result()
                        if result:
                            matched_account = result
                            # Cancel remaining futures
                            for f in futures:
                                f.cancel()
                            break

                if matched_account:
                    print(f"[+] Key matches: {matched_account}")

        if not matched_account:
            # Fallback: use first unassigned or first account
            if accounts:
                unassigned = [a for a in accounts if a['folder'] not in config.get('accounts', {})]
                matched_account = unassigned[0]['folder'] if unassigned else accounts[0]['folder']
            else:
                matched_account = 'unknown'
            print(f"[?] Could not verify, using: {matched_account}")

        # Save config
        config = set_account_key(config, matched_account, key)
        save_config(config)

        return key
    else:
        print("[!] Failed to extract key")
        return None


def get_account_nickname(key, account_folder):
    """Decrypt contact.db and get account nickname"""
    data_dir = find_wechat_data_dir()
    if not data_dir or not account_folder:
        return None

    contact_src = data_dir / account_folder / "db_storage" / "contact" / "contact.db"
    if not contact_src.exists():
        return None

    OUTPUT_DIR.mkdir(exist_ok=True)
    contact_dst = OUTPUT_DIR / "contact.db"

    result = subprocess.run(
        [str(DUMP_EXE), '-k', key, '-f', str(contact_src), '-o', str(contact_dst), '--vv', '4'],
        capture_output=True, text=True
    )

    if not contact_dst.exists():
        return None

    try:
        conn = sqlite3.connect(str(contact_dst))
        cur = conn.cursor()
        wxid_base = account_folder.rsplit('_', 1)[0]
        cur.execute('SELECT nick_name FROM contact WHERE username = ?', (wxid_base,))
        row = cur.fetchone()
        conn.close()
        return row[0] if row else None
    except:
        return None


def login_account():
    """Full login flow: extract key → get nickname → prompt for history import → sync"""
    key = extract_key()
    if not key:
        return False

    # Get account info
    config = load_config()
    active_acc, acc_config = get_active_account(config)

    # Decrypt contact.db immediately to get nickname
    nickname = get_account_nickname(key, active_acc)
    if nickname:
        config['accounts'][active_acc]['nickname'] = nickname
        save_config(config)

    display_name = nickname or active_acc
    print()
    print("=" * 50)
    print(f"  {display_name} logged in!")
    print()
    print("  Now import your chat history in WeChat:")
    print("  Settings → General → Chat History → Import")
    print("=" * 50)
    print()
    print("Press Enter when chat history import is complete...")

    try:
        input()
    except:
        pass

    print()
    sync_databases(key=key, force=True)

    print()
    print(f"[+] {display_name} - login complete!")
    return True


# ============================================================
# Sync (Decrypt)
# ============================================================

def sync_databases(key=None, account_folder=None, force=False):
    """Decrypt databases (incremental - only changed files)"""
    config = load_config()

    # Get active account
    active_acc, acc_config = get_active_account(config)
    key = key or acc_config.get('key')
    account_folder = account_folder or active_acc

    if not key:
        print("[!] No key found. Run: wechat login")
        return False

    dbs = find_databases(account_folder)
    if not dbs:
        print("[!] No databases found")
        return False

    # Also add contact.db
    data_dir = find_wechat_data_dir()
    if data_dir and account_folder:
        contact_src = data_dir / account_folder / "db_storage" / "contact" / "contact.db"
        if contact_src.exists():
            dbs.append({
                'path': contact_src,
                'account': account_folder,
                'name': 'contact.db',
                'size': contact_src.stat().st_size
            })

    OUTPUT_DIR.mkdir(exist_ok=True)

    # Get previously synced DB info
    synced_dbs = acc_config.get('synced_dbs', {})

    # Determine which DBs need syncing
    to_sync = []
    skipped = 0
    for db in dbs:
        db_name = db['name']
        src_mtime = db['path'].stat().st_mtime

        prev_sync = synced_dbs.get(db_name, {})
        prev_mtime = prev_sync.get('mtime', 0)

        if force or src_mtime > prev_mtime:
            to_sync.append(db)
        else:
            skipped += 1

    if not to_sync:
        print(f"[*] All {len(dbs)} database(s) up to date")
        return True

    if skipped > 0:
        print(f"[*] {skipped} database(s) unchanged, syncing {len(to_sync)}...")
    else:
        print(f"[*] Syncing {len(to_sync)} database(s)...")

    success_count = 0
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    for db in to_sync:
        out_name = f"{db['account']}_{db['name']}"
        out_path = OUTPUT_DIR / out_name

        result = subprocess.run(
            [str(DUMP_EXE), '-k', key, '-f', str(db['path']), '-o', str(out_path), '--vv', '4'],
            capture_output=True, text=True
        )

        if out_path.exists():
            print(f"    {db['name']}: OK")
            success_count += 1

            # Record sync info
            synced_dbs[db['name']] = {
                'mtime': db['path'].stat().st_mtime,
                'synced_at': now,
                'size': db['path'].stat().st_size
            }
        else:
            print(f"    {db['name']}: FAILED")

    # Update config
    if active_acc and active_acc in config.get('accounts', {}):
        config['accounts'][active_acc]['last_sync'] = now
        config['accounts'][active_acc]['synced_dbs'] = synced_dbs
    save_config(config)

    # Count stats from synced databases
    stats = count_sync_stats(account_folder)

    print(f"[+] Synced {success_count}/{len(to_sync)} databases")
    if stats['chats'] > 0 or stats['contacts'] > 0:
        parts = []
        if stats['chats'] > 0:
            parts.append(f"{stats['chats']} chats")
        if stats['messages'] > 0:
            parts.append(f"{stats['messages']} messages")
        if stats['contacts'] > 0:
            parts.append(f"{stats['contacts']} contacts")
        if stats['media_size'] > 0:
            media_gb = stats['media_size'] / 1024 / 1024 / 1024
            parts.append(f"{media_gb:.1f}GB media")
        print(f"    ({', '.join(parts)})")

    return success_count > 0


def count_sync_stats(account_folder):
    """Count chats, messages, contacts, and media from synced databases"""
    stats = {'chats': 0, 'messages': 0, 'contacts': 0, 'media_size': 0}

    # Count chats and messages from message DBs
    for db_file in OUTPUT_DIR.glob(f"{account_folder}_message_*.db"):
        if 'fts' in db_file.name or 'resource' in db_file.name:
            continue
        try:
            conn = sqlite3.connect(str(db_file))
            cur = conn.cursor()
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Msg_%'")
            tables = [t[0] for t in cur.fetchall()]

            for table in tables:
                cur.execute(f'SELECT COUNT(*) FROM {table}')
                count = cur.fetchone()[0]
                if count > 0:
                    stats['chats'] += 1
                    stats['messages'] += count
            conn.close()
        except:
            pass

    # Count contacts
    contact_db = OUTPUT_DIR / "contact.db"
    if contact_db.exists():
        try:
            conn = sqlite3.connect(str(contact_db))
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM contact WHERE username IS NOT NULL AND username != ''")
            stats['contacts'] = cur.fetchone()[0]
            conn.close()
        except:
            pass

    # Count media size from source folder
    data_dir = find_wechat_data_dir()
    if data_dir and account_folder:
        msg_dir = data_dir / account_folder / "msg"
        if msg_dir.exists():
            import os
            for dirpath, dirnames, filenames in os.walk(msg_dir):
                for f in filenames:
                    try:
                        stats['media_size'] += os.path.getsize(os.path.join(dirpath, f))
                    except:
                        pass

    return stats


# ============================================================
# Search
# ============================================================

def decompress(data):
    if not data:
        return ''
    if isinstance(data, str):
        return data
    if isinstance(data, bytes) and len(data) >= 4 and data[:4] == b'\x28\xb5\x2f\xfd':
        if HAS_ZSTD:
            try:
                return zstd.ZstdDecompressor().decompress(data).decode('utf-8', errors='replace')
            except:
                return ''
        return ''
    if isinstance(data, bytes):
        return data.decode('utf-8', errors='replace')
    return str(data)


import hashlib

def load_contacts(account_filter=None):
    """Load contact display names from contact.db files"""
    contacts = {}

    # Find contact databases
    if account_filter:
        # Find matching account
        matched_wxid = find_account_wxid(account_filter)
        if matched_wxid:
            contact_dbs = list(OUTPUT_DIR.glob(f"{matched_wxid}_contact.db"))
        else:
            contact_dbs = []
    else:
        # Load from all contact databases
        contact_dbs = list(OUTPUT_DIR.glob("*_contact.db"))
        # Also check legacy contact.db
        legacy_db = OUTPUT_DIR / "contact.db"
        if legacy_db.exists() and legacy_db not in contact_dbs:
            contact_dbs.append(legacy_db)

    for contact_db in contact_dbs:
        try:
            conn = sqlite3.connect(str(contact_db))
            cur = conn.cursor()
            cur.execute("SELECT username, nick_name, remark FROM contact WHERE username IS NOT NULL")
            for row in cur.fetchall():
                username = row[0]
                # Prefer remark (user-set name), then nickname
                display = row[2] or row[1] or username
                contacts[username] = {
                    'display': display,
                    'nick_name': row[1] or '',
                    'remark': row[2] or ''
                }
            conn.close()
        except:
            pass

    return contacts


def find_account_wxid(query):
    """Find account wxid by nickname or partial wxid match"""
    config = load_config()
    accounts = config.get('accounts', {})
    query_lower = query.lower()

    for wxid, acc in accounts.items():
        nickname = acc.get('nickname', '').lower()
        if query_lower in nickname or query_lower in wxid.lower():
            return wxid
    return None


def find_contact_by_name(query, contacts):
    """Fuzzy match contact by nick_name or remark"""
    query_lower = query.lower()
    matches = []

    for username, info in contacts.items():
        nick = info['nick_name'].lower()
        remark = info['remark'].lower()
        display = info['display']

        # Exact match first
        if query_lower == nick or query_lower == remark:
            return [(username, display, 100)]

        # Partial match
        score = 0
        if query_lower in nick:
            score = 80
        elif query_lower in remark:
            score = 70
        elif query_lower in display.lower():
            score = 60

        if score > 0:
            matches.append((username, display, score))

    # Sort by score descending
    matches.sort(key=lambda x: x[2], reverse=True)
    return matches[:5]


def show_chat_messages(username, display_name, limit=30):
    """Show recent messages from a specific chat"""
    table_name = username_to_table(username)

    messages = []
    for db_file in OUTPUT_DIR.glob("*_message_*.db"):
        if 'fts' in db_file.name or 'resource' in db_file.name:
            continue
        try:
            conn = sqlite3.connect(str(db_file))
            cur = conn.cursor()
            cur.execute(f'''
                SELECT create_time, message_content, compress_content, local_type
                FROM {table_name}
                ORDER BY create_time DESC
                LIMIT ?
            ''', (limit,))
            rows = cur.fetchall()
            conn.close()

            for row in rows:
                content = decompress(row[1]) or decompress(row[2])
                if content:
                    messages.append({
                        'time': row[0],
                        'content': content,
                        'is_received': row[3] == 1
                    })
        except:
            continue

    if not messages:
        print(f"No messages found with {display_name}")
        return

    messages.sort(key=lambda x: x['time'] or 0)

    print(f"\n[{display_name}] {len(messages)} recent messages")
    print("=" * 60)

    for msg in messages:
        ts = datetime.fromtimestamp(msg['time']).strftime('%m-%d %H:%M') if msg['time'] else '??'
        direction = '[Ta]' if msg['is_received'] else '[我]'
        content = msg['content'].strip()
        content = ' '.join(content.split())  # normalize whitespace

        # Skip XML/system messages
        if content.startswith('<') and '>' in content:
            continue

        print(f"{ts} {direction} {content}")


def username_to_table(username):
    """Convert username to Msg table name"""
    return f"Msg_{hashlib.md5(username.encode()).hexdigest()}"


def table_to_username(table_name, contacts):
    """Find username for a table by checking MD5 hashes"""
    table_hash = table_name.replace('Msg_', '')
    for username in contacts:
        if hashlib.md5(username.encode()).hexdigest() == table_hash:
            return username
    return None


def get_context_messages(cur, table, target_time, context=2):
    """Get messages around a specific time for context"""
    messages = []
    try:
        # Get messages around the target time
        cur.execute(f'''
            SELECT create_time, message_content, compress_content, local_type
            FROM {table}
            WHERE create_time >= ? - 300 AND create_time <= ? + 300
            ORDER BY create_time ASC
        ''', (target_time, target_time))

        rows = cur.fetchall()
        target_idx = None

        for i, row in enumerate(rows):
            if row[0] == target_time:
                target_idx = i
                break

        if target_idx is not None:
            start = max(0, target_idx - context)
            end = min(len(rows), target_idx + context + 1)

            for i in range(start, end):
                row = rows[i]
                content = decompress(row[1]) or decompress(row[2])
                if content:
                    messages.append({
                        'time': row[0],
                        'content': content,
                        'is_match': (i == target_idx),
                        'type': row[3]  # 1 = received, others = sent
                    })
    except:
        pass

    return messages


def parse_search_query(query):
    """
    Parse search query with contact filter and AND/OR terms.

    Syntax:
        "keyword"                    - single term, all chats
        "contact: keyword"           - search in contact's chat
        "term1 term2"                - OR logic (default)
        "+term1 +term2"              - AND logic (all required)
        "contact: +term1 term2"      - in contact, must have term1, plus term2

    Returns: (contact_query, and_terms, or_terms)
    """
    contact_query = None
    and_terms = []
    or_terms = []

    # Check for contact filter
    if ':' in query:
        parts = query.split(':', 1)
        contact_query = parts[0].strip()
        keywords = parts[1].strip()
    else:
        keywords = query.strip()

    # Parse terms
    if keywords:
        for term in keywords.split():
            term = term.strip()
            if not term:
                continue
            if term.startswith('+'):
                and_terms.append(term[1:].lower())
            else:
                or_terms.append(term.lower())

    return contact_query, and_terms, or_terms


def matches_terms(content, and_terms, or_terms):
    """Check if content matches the search terms."""
    content_lower = content.lower()

    # All AND terms must be present
    for term in and_terms:
        if term not in content_lower:
            return False

    # If no OR terms, AND terms are enough
    if not or_terms:
        return len(and_terms) > 0

    # At least one OR term must be present
    for term in or_terms:
        if term in content_lower:
            return True

    # If we have AND terms but no OR terms matched, still return True
    # (AND terms already validated above)
    return len(and_terms) > 0 and len(or_terms) == 0


def search_messages(query, limit=10, account_filter=None):
    """Search messages with contact filter and AND/OR term support."""
    if not OUTPUT_DIR.exists():
        print(f"[!] Data directory not found: {OUTPUT_DIR}")
        if sys.platform == 'darwin':
            print("    Mount SMB share: open smb://asus-wsl-ubuntu/edrive")
        return

    # Filter database files by account
    if account_filter:
        matched_wxid = find_account_wxid(account_filter)
        if matched_wxid:
            db_files = list(OUTPUT_DIR.glob(f"{matched_wxid}_message_*.db"))
        else:
            print(f"[!] Account not found: {account_filter}")
            return
    else:
        db_files = list(OUTPUT_DIR.glob("*_message_*.db"))

    # Exclude fts and resource databases
    db_files = [f for f in db_files if 'fts' not in f.name and 'resource' not in f.name]

    if not db_files:
        print("[!] No message databases found")
        return

    # Load contacts
    contacts = load_contacts(account_filter=account_filter)

    # Parse query
    contact_query, and_terms, or_terms = parse_search_query(query)

    # If only contact specified (no keywords), show that chat
    if contact_query and not and_terms and not or_terms:
        contact_matches = find_contact_by_name(contact_query, contacts)
        if contact_matches:
            best_match = contact_matches[0]
            username, display, score = best_match
            show_chat_messages(username, display)
            return
        else:
            print(f"No contact found matching: {contact_query}")
            return

    # If no keywords at all, try contact match on the whole query
    if not and_terms and not or_terms:
        contact_matches = find_contact_by_name(query, contacts)
        if contact_matches:
            best_match = contact_matches[0]
            username, display, score = best_match
            if len(contact_matches) > 1 and score < 100:
                print(f"\nFound {len(contact_matches)} contacts matching '{query}':")
                for u, d, s in contact_matches:
                    print(f"  - {d}")
                print(f"\nShowing messages with: {display}")
            show_chat_messages(username, display)
            return

    # Find target contact if specified
    target_username = None
    target_display = None
    if contact_query:
        contact_matches = find_contact_by_name(contact_query, contacts)
        if contact_matches:
            target_username, target_display, _ = contact_matches[0]
        else:
            print(f"No contact found matching: {contact_query}")
            return

    # Build search description
    search_desc = []
    if and_terms:
        search_desc.append(f"AND({', '.join(and_terms)})")
    if or_terms:
        search_desc.append(f"OR({', '.join(or_terms)})")
    search_str = ' + '.join(search_desc) if search_desc else query

    # Results grouped by chat
    chat_results = {}  # username -> {'matches': [], 'last_time': int, 'display': str}

    for db_file in db_files:
        try:
            conn = sqlite3.connect(str(db_file))
            cur = conn.cursor()

            # Build table -> username mapping from Name2Id
            table_usernames = {}
            try:
                cur.execute("SELECT user_name FROM Name2Id")
                for row in cur.fetchall():
                    username = row[0]
                    if username:
                        table_name = username_to_table(username)
                        table_usernames[table_name] = username
            except:
                pass

            # Get all Msg tables
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Msg_%'")
            tables = [t[0] for t in cur.fetchall()]

            for table in tables:
                username = table_usernames.get(table) or table_to_username(table, contacts) or table

                # Skip if filtering by contact and this isn't the target
                if target_username and username != target_username:
                    continue

                contact_info = contacts.get(username, {})
                display_name = contact_info.get('display', username) if isinstance(contact_info, dict) else username

                # Search in this table
                try:
                    # Get all messages (we'll filter in Python for complex logic)
                    cur.execute(f'''
                        SELECT create_time, message_content, compress_content
                        FROM {table}
                        ORDER BY create_time DESC
                    ''')

                    for row in cur.fetchall():
                        content = decompress(row[1]) or decompress(row[2])
                        if content and matches_terms(content, and_terms, or_terms):
                            if username not in chat_results:
                                chat_results[username] = {
                                    'display': display_name,
                                    'matches': [],
                                    'last_time': 0,
                                    'table': table
                                }

                            chat_results[username]['matches'].append({
                                'time': row[0],
                                'content': content
                            })

                            if row[0] and row[0] > chat_results[username]['last_time']:
                                chat_results[username]['last_time'] = row[0]
                except:
                    continue

            conn.close()
        except Exception as e:
            continue

    if not chat_results:
        print(f"No messages found for: {search_str}")
        return

    # Sort chats by most recent match
    sorted_chats = sorted(chat_results.items(), key=lambda x: x[1]['last_time'], reverse=True)

    total_matches = sum(len(c['matches']) for _, c in sorted_chats)
    contact_note = f" in [{target_display}]" if target_display else ""
    print(f"\nFound {total_matches} match(es){contact_note} for: {search_str}")
    print("=" * 60)

    # Display grouped results
    shown_chats = 0
    for username, chat in sorted_chats:
        if shown_chats >= limit:
            remaining = len(sorted_chats) - shown_chats
            if remaining > 0:
                print(f"\n... and {remaining} more chat(s)")
            break

        display = chat['display']
        match_count = len(chat['matches'])
        last_time = datetime.fromtimestamp(chat['last_time']).strftime('%m-%d') if chat['last_time'] else '??'

        # Chat header
        is_group = '@chatroom' in username
        chat_type = 'group' if is_group else 'chat'
        print(f"\n[{display}] {match_count} match(es) | {last_time}")
        print("-" * 40)

        # Show up to 5 matches per chat
        for i, match in enumerate(chat['matches'][:5]):
            ts = datetime.fromtimestamp(match['time']).strftime('%m-%d %H:%M') if match['time'] else '??'
            content = match['content'].strip()

            # Show full message, just clean up whitespace
            content = ' '.join(content.split())  # normalize whitespace

            print(f"  {ts}  {content}")

        if match_count > 5:
            print(f"  ... +{match_count - 5} more")

        shown_chats += 1


def list_chats(account_filter=None):
    """List all chats with message counts"""
    if not OUTPUT_DIR.exists():
        print(f"[!] Data directory not found: {OUTPUT_DIR}")
        if sys.platform == 'darwin':
            print("    Mount SMB share: open smb://asus-wsl-ubuntu/edrive")
        return

    # Filter database files by account
    if account_filter:
        matched_wxid = find_account_wxid(account_filter)
        if matched_wxid:
            db_files = list(OUTPUT_DIR.glob(f"{matched_wxid}_message_*.db"))
        else:
            print(f"[!] Account not found: {account_filter}")
            return
    else:
        db_files = list(OUTPUT_DIR.glob("*_message_*.db"))

    # Exclude fts and resource databases
    db_files = [f for f in db_files if 'fts' not in f.name and 'resource' not in f.name]

    if not db_files:
        print("[!] No message databases found")
        return

    contacts = load_contacts(account_filter=account_filter)
    # Use dict to merge stats for same username
    chat_stats = {}  # username -> {display, count, last_time, is_group}

    for db_file in db_files:
        try:
            conn = sqlite3.connect(str(db_file))
            cur = conn.cursor()

            # Build table -> username mapping
            table_usernames = {}
            try:
                cur.execute("SELECT user_name FROM Name2Id")
                for row in cur.fetchall():
                    username = row[0]
                    if username:
                        table_name = username_to_table(username)
                        table_usernames[table_name] = username
            except:
                pass

            # Get all Msg tables with counts
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Msg_%'")
            tables = [t[0] for t in cur.fetchall()]

            for table in tables:
                username = table_usernames.get(table) or table_to_username(table, contacts) or table
                contact_info = contacts.get(username, {})
                display_name = contact_info.get('display', username) if isinstance(contact_info, dict) else username

                try:
                    cur.execute(f"SELECT COUNT(*), MAX(create_time) FROM {table}")
                    row = cur.fetchone()
                    msg_count = row[0] or 0
                    last_time = row[1] or 0

                    if msg_count > 0:
                        if username in chat_stats:
                            # Merge: add count, keep latest time
                            chat_stats[username]['count'] += msg_count
                            if last_time > chat_stats[username]['last_time']:
                                chat_stats[username]['last_time'] = last_time
                        else:
                            chat_stats[username] = {
                                'display': display_name,
                                'count': msg_count,
                                'last_time': last_time,
                                'is_group': '@chatroom' in username
                            }
                except:
                    continue

            conn.close()
        except:
            continue

    if not chat_stats:
        print("No chats found")
        return

    # Convert to list and sort by last message time
    chats = [(username, stats) for username, stats in chat_stats.items()]
    chats.sort(key=lambda x: x[1]['last_time'], reverse=True)

    print(f"\n{len(chats)} chat(s)")
    print("=" * 60)

    for username, chat in chats[:30]:
        ts = datetime.fromtimestamp(chat['last_time']).strftime('%m-%d') if chat['last_time'] else '??'
        display = chat['display'][:25]
        print(f"  [{ts}] {display:25} ({chat['count']} msgs)")

    if len(chats) > 30:
        print(f"\n  ... and {len(chats) - 30} more")


# ============================================================
# Status Check
# ============================================================

def display_width(s):
    """Calculate display width (Chinese chars = 2, others = 1)"""
    import unicodedata
    width = 0
    for c in s:
        if unicodedata.east_asian_width(c) in ('F', 'W'):
            width += 2
        else:
            width += 1
    return width


def pad_to_width(s, width):
    """Pad string to target display width"""
    current = display_width(s)
    return s + ' ' * (width - current)


def show_accounts():
    """Show compact account list"""
    config = load_config()
    accounts = config.get('accounts', {})
    active = config.get('active')

    if not accounts:
        print("[!] No accounts. Run: wechat login\n")
        return False

    for wxid, acc in accounts.items():
        nickname = acc.get('nickname', wxid)
        marker = '*' if wxid == active else ' '
        last_sync = acc.get('last_sync', 'never')
        sync_date = last_sync.split(' ')[0] if last_sync != 'never' else 'never'
        padded_name = pad_to_width(nickname, 24)
        print(f"  {marker} {padded_name} [{sync_date}]")
    print()
    return True


def show_help():
    """Show available commands"""
    print("Commands:")
    print("  login          Login new account")
    print("  sync           Decrypt latest messages")
    print("  search <q>     Search messages")
    print()


def show_search_help():
    """Show search command help"""
    print("Search:")
    print("  search <query>                 Search messages (all accounts)")
    print("  search --account <name> <q>    Search in specific account")
    print("  search --chats                 List all chats")
    print("  search --chats --account <n>   List chats in specific account")
    print()


def check_status():
    """Check and display status"""
    config = load_config()

    # Get active account
    active_acc, acc_config = get_active_account(config)
    key = acc_config.get('key')
    last_sync = acc_config.get('last_sync')

    print()

    # Check WeChat running
    pid = get_wechat_pid()

    # List all accounts
    all_accounts = config.get('accounts', {})

    if not key:
        print("[!] No key found")
        if all_accounts:
            print(f"    Accounts with keys: {list(all_accounts.keys())}")
        print()
        return 'no_key'

    # Validate key
    valid, info = validate_key(key, active_acc)

    if not valid:
        print(f"[!] Key invalid: {info}")
        print()
        return 'invalid_key'

    show_accounts()
    show_help()
    return 'ok'


# ============================================================
# Main CLI
# ============================================================

def main():
    args = sys.argv[1:]

    if not args:
        # Default: check status
        status = check_status()

        if status == 'no_key':
            print("Login new account? [Y/n]: ", end='')
            try:
                resp = input().strip().lower()
            except:
                resp = 'y'

            if resp != 'n':
                login_account()

        elif status == 'invalid_key':
            print("Key is invalid. Re-login? [Y/n]: ", end='')
            try:
                resp = input().strip().lower()
            except:
                resp = 'y'

            if resp != 'n':
                login_account()

        return

    cmd = args[0].lower()

    if cmd == 'check':
        check_status()

    elif cmd == 'login' or cmd == 'extract':  # extract kept for backwards compatibility
        login_account()

    elif cmd == 'sync':
        force = '--force' in args or '-f' in args
        sync_databases(force=force)

    elif cmd == 'search':
        # Parse --account and --chats flags
        account_filter = None
        show_chats = False
        query_parts = []

        i = 1
        while i < len(args):
            if args[i] == '--account' and i + 1 < len(args):
                account_filter = args[i + 1]
                i += 2
            elif args[i] == '--chats':
                show_chats = True
                i += 1
            else:
                query_parts.append(args[i])
                i += 1

        if show_chats:
            list_chats(account_filter=account_filter)
        elif query_parts:
            query = ' '.join(query_parts)
            search_messages(query, account_filter=account_filter)
        else:
            show_accounts()
            show_search_help()

    elif cmd == 'account':
        show_accounts()

    else:
        show_accounts()
        show_help()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nCancelled")
        sys.exit(1)
    except Exception as e:
        print(f"\n[!] Error: {e}")
        sys.exit(1)
