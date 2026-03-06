#!/usr/bin/env python3
"""
permHelper.py

A command-line tool to explain and inspect Linux file/directory permissions.
"""

import os
import stat
import click
import re
from tabulate import tabulate

# --------------- Symbolic / Octal Constants ---------------

# Valid actions, “who,” and “permission” characters
ACTIONS = ('+', '-', '=')
WHO     = ('u', 'g', 'o', 'a')
PERMS   = ('r', 'w', 'x')

# Precompute explanations for any single-symbolic operation (e.g. “u+x”, “g=w”, etc.)
def generate_symbolic_explanations():
    """
    Build a dict mapping strings like "u+x" or "g=w" → human‐readable English.
    """
    explanations = {}
    for who in WHO:
        for perm in PERMS:
            for action in ACTIONS:
                key = f"{who}{action}{perm}"
                entity_word = {
                    'u': 'user (owner)',
                    'g': 'group',
                    'o': 'others',
                    'a': 'all (user, group, and others)'
                }[who]
                perm_word = {
                    'r': 'read',
                    'w': 'write',
                    'x': 'execute'
                }[perm]
                action_word = {
                    '+': 'Adds',
                    '-': 'Removes',
                    '=': 'Sets exactly'
                }[action]
                explanations[key] = f"{action_word} {perm_word} permission for the {entity_word}"
    return explanations

SYMBOLIC_PERM_EXPLANATIONS = generate_symbolic_explanations()

# Octal → [symbolic, description] table for digits 0–7
OCTAL_TABLE = [
    #       Octal  Symbolic  Description
    ["Octal", "Symbolic", "Description"],
    ["0",     "---",      "No permissions"],
    ["1",     "--x",      "Execute only"],
    ["2",     "-w-",      "Write only"],
    ["3",     "-wx",      "Write & execute"],
    ["4",     "r--",      "Read only"],
    ["5",     "r-x",      "Read & execute"],
    ["6",     "rw-",      "Read & write"],
    ["7",     "rwx",      "Read, write & execute"]
]

# --------------- Helper Functions (Core Logic) ---------------

def octal_to_symbolic(octal_str):
    """
    Convert a 3-digit octal string (e.g. "755" or "0644") into:
      - symbolic string (e.g. "rwxr-xr-x")
      - a list of human‐readable lines describing each entity’s permissions
    Returns (symbolic_str, [descriptions]) if valid, else None.
    """
    # Allow optional leading '0' (e.g. "0644")
    if len(octal_str) == 4 and octal_str.startswith('0'):
        octal_str = octal_str[1:]

    if not re.fullmatch(r"[0-7]{3}", octal_str):
        return None

    symbolic_full = ""
    descriptions = []

    for idx, digit_char in enumerate(octal_str):
        digit = int(digit_char)
        # OCTAL_TABLE is 1-indexed by digit, so index = digit + 1
        symbolic_triplet = OCTAL_TABLE[digit + 1][1]  # e.g. "rwx", "r-x", etc.
        entity_label = ("User", "Group", "Others")[idx]
        symbolic_full += symbolic_triplet

        # Build a comma-separated list of active bits
        desc_parts = []
        if "r" in symbolic_triplet: desc_parts.append("read")
        if "w" in symbolic_triplet: desc_parts.append("write")
        if "x" in symbolic_triplet: desc_parts.append("execute")
        if not desc_parts:
            desc_parts = ["no permissions"]

        descriptions.append(f"{entity_label}: {', '.join(desc_parts)}")

    return symbolic_full, descriptions


def get_symbolic_explanation(symbolic_perm):
    """
    Given a single symbolic string like "u+x" or "g=rw", return a human explanation.
    If it’s not recognized, return None.
    (Note: We only precompute single-op combos such as “u+x”, “a-w”, “g=r”.)
    """
    return SYMBOLIC_PERM_EXPLANATIONS.get(symbolic_perm)


def describe_path_permissions(path):
    """
    Return a dict of permission information for ANY path (file or directory):
      {
        "path": <the original path>,
        "owner_uid": ...,
        "group_gid": ...,
        "symbolic_mode": e.g. "-rwxr-xr-x",
        "octal_mode": e.g. "0755" (string),
        "user_permissions": "User: read, write", etc,
        "group_permissions": ...,
        "others_permissions": ...
      }
    """
    st = os.stat(path)
    mode = st.st_mode
    umode = stat.S_IMODE(mode)  # strip file‐type bits

    # Build human‐readable segment for one entity
    def _entity_perms(bits_mask, shift, name):
        bits_present = []
        # shift the mode to align with owner‐bits, since stat.S_IRUSR etc. refer to user
        if umode & bits_mask: bits_present.append(name)
        return bits_present

    # Instead of shifting manually, use stat.filemode() for symbolic
    symbolic_mode = stat.filemode(umode)

    # Octal string (always 3 digits, leading zero if needed)
    octal_mode = f"{umode:03o}"

    # Build “User: ..., Group: ..., Others: …”
    def _entity_str(entity_idx):
        # entity_idx: 0=user, 1=group, 2=others
        labels = ["User", "Group", "Others"]
        shifts = [6, 3, 0]
        perms_list = []
        mask_r = 0o400 >> (3 * entity_idx)
        mask_w = 0o200 >> (3 * entity_idx)
        mask_x = 0o100 >> (3 * entity_idx)

        if umode & mask_r: perms_list.append("read")
        if umode & mask_w: perms_list.append("write")
        if umode & mask_x: perms_list.append("execute")
        if not perms_list:
            perms_list = ["no permissions"]
        return f"{labels[entity_idx]}: {', '.join(perms_list)}"

    return {
        "path": os.path.abspath(path),
        "owner_uid": st.st_uid,
        "group_gid": st.st_gid,
        "symbolic_mode": symbolic_mode,
        "octal_mode": octal_mode,
        "user_permissions": _entity_str(0),
        "group_permissions": _entity_str(1),
        "others_permissions": _entity_str(2)
    }


def list_directory_permissions(directory, recursive=False):
    """
    Walk a directory (single level or recursively) and return a list of dicts,
    each dict is the output of describe_path_permissions() for that path.
    """
    results = []
    for entry in os.scandir(directory):
        try:
            info = describe_path_permissions(entry.path)
            results.append(info)
        except PermissionError:
            # If we can’t stat a particular file
            results.append({
                "path": entry.path,
                "error": "Permission denied"
            })

        if recursive and entry.is_dir(follow_symlinks=False):
            # Recurse into subdirectory
            sub_results = list_directory_permissions(entry.path, recursive=True)
            results.extend(sub_results)

    return results


# --------------- CLI (Click Group & Commands) ---------------

@click.group(context_settings={"help_option_names": ["-h", "--help"]})
@click.version_option(version="1.3.0", prog_name="permHelper")
@click.option(
    "--verbose", "-v",
    is_flag=True,
    help="Show extra debugging output when inspecting permissions."
)
@click.pass_context
def cli(ctx, verbose):
    """
    permHelper: A Linux Permissions Helper Tool.

    You can:

      • `explain <perm>`         → Explain a symbolic or octal permission string  
      • `table`                   → Show the octal ↔ symbolic ASCII table  
      • `check-file <path>`       → Check permissions for a single file  
      • `check-dir <directory>`   → Check permissions for a directory (and optionally subdirectories)
    """
    ctx.ensure_object(dict)
    ctx.obj["VERBOSE"] = verbose


@cli.command()
@click.argument("perm", metavar="<symbolic|octal>", required=True)
def explain(perm):
    """
    Explain a symbolic (e.g. u+x or a-w) or octal (e.g. 755 or 0644) permission.
    """
    perm = perm.strip()

    # First, see if it's an octal string
    if re.fullmatch(r"0?[0-7]{3}", perm):
        result = octal_to_symbolic(perm)
        if not result:
            click.secho("Invalid octal permission. Must be 3 digits in [0-7].", fg="red")
            return

        symbolic, descs = result
        click.secho(f"\nOctal: {perm}", fg="green", bold=True)
        click.echo(f"Symbolic (rwx form): {symbolic}")
        click.echo("Meaning per entity:")
        for line in descs:
            click.echo(f"  - {line}")
        return

    # Next, see if it matches our single-op symbolic table (e.g. u+r, g=rx, a-w)
    explanation = get_symbolic_explanation(perm)
    if explanation:
        click.secho(f"\nSymbolic: {perm}", fg="green", bold=True)
        click.echo(f"{explanation}")
        click.echo(f"Equivalent command: chmod {perm} <filename>")
    else:
        click.secho("Invalid or unsupported permission string.", fg="red")
        click.echo("Examples of valid inputs: u+x, g=rw, o-x, 755, 0644.")



@cli.command()
def table():
    """
    Display comprehensive Linux permission tables:
      • Octal digit → binary → symbolic
      • u/g/o positional meaning
      • Common real-world permission examples
    """
    click.secho("\nOctal Digit Breakdown", fg="cyan", bold=True)

    digit_table = [
        ["Octal", "Binary", "Symbolic", "Meaning"],
        ["0", "000", "---", "No permissions"],
        ["1", "001", "--x", "Execute"],
        ["2", "010", "-w-", "Write"],
        ["3", "011", "-wx", "Write, execute"],
        ["4", "100", "r--", "Read"],
        ["5", "101", "r-x", "Read, execute"],
        ["6", "110", "rw-", "Read, write"],
        ["7", "111", "rwx", "Read, write, execute"],
    ]
    click.echo(tabulate(digit_table, headers="firstrow", tablefmt="github"))

    click.secho("\nPermission Position Meaning (u/g/o)", fg="cyan", bold=True)
    position_table = [
        ["Digit position", "Entity", "Applies to"],
        ["1st", "User (owner)", "File owner"],
        ["2nd", "Group", "File group"],
        ["3rd", "Others", "Everyone else"],
    ]
    click.echo(tabulate(position_table, headers="firstrow", tablefmt="github"))

    click.secho("\nCommon Permission Examples", fg="cyan", bold=True)
    common_modes = [
        ["Octal", "Symbolic", "User", "Group", "Others", "Typical use"],
        ["644", "rw-r--r--", "read/write", "read", "read", "Text files"],
        ["600", "rw-------", "read/write", "—", "—", "Secrets, SSH keys"],
        ["700", "rwx------", "full", "—", "—", "Private scripts"],
        ["755", "rwxr-xr-x", "full", "read/execute", "read/execute", "Directories, binaries"],
        ["777", "rwxrwxrwx", "full", "full", "full", "Almost always a bad idea"],
    ]
    click.echo(tabulate(common_modes, headers="firstrow", tablefmt="github"))



@cli.command("check-file")
@click.argument("path", type=click.Path(exists=True, file_okay=True, dir_okay=False))
@click.pass_context
def check_file(ctx, path):
    """
    Check and explain permissions for a single file.

    Example: 
      permHelper.py check-file ./some_script.sh
    """
    verbose = ctx.obj.get("VERBOSE", False)
    try:
        info = describe_path_permissions(path)
    except FileNotFoundError:
        click.secho(f"File not found: {path}", fg="red")
        return
    except PermissionError:
        click.secho(f"Permission denied: {path}", fg="red")
        return

    # Print results
    click.secho(f"\nPermissions for file: {info['path']}", fg="cyan", bold=True)
    click.echo(f"Owner UID        : {info['owner_uid']}")
    click.echo(f"Group GID        : {info['group_gid']}")
    click.echo(f"Symbolic Mode    : {info['symbolic_mode']}")
    click.echo(f"Octal Mode       : {info['octal_mode']}")
    click.echo(f"User Permissions : {info['user_permissions']}")
    click.echo(f"Group Permissions: {info['group_permissions']}")
    click.echo(f"Others Permissions: {info['others_permissions']}")

    if verbose:
        click.secho("\n[DEBUG] Raw st_mode bits:", fg="yellow")
        st = os.stat(path)
        click.echo(f"  st_mode: {oct(st.st_mode)}")


@cli.command("dir")
@click.argument("directory", type=click.Path(exists=True, file_okay=False, dir_okay=True))
@click.option(
    "--recursive", "-r",
    is_flag=True,
    help="Recursively walk subdirectories and list permissions for all files."
)
@click.pass_context
def dir(ctx, directory, recursive):
    """
    Check permissions for a directory and list its immediate contents (or recursively if -r).

    Example:
      permHelper.py check-dir /var/www/html
      permHelper.py check-dir -r /home/user/Documents
    """
    verbose = ctx.obj.get("VERBOSE", False)

    # First, describe the directory itself
    try:
        dir_info = describe_path_permissions(directory)
    except FileNotFoundError:
        click.secho(f"Directory not found: {directory}", fg="red")
        return
    except PermissionError:
        click.secho(f"Permission denied: {directory}", fg="red")
        return

    click.secho(f"\nPermissions for directory: {dir_info['path']}", fg="cyan", bold=True)
    click.echo(f"Owner UID        : {dir_info['owner_uid']}")
    click.echo(f"Group GID        : {dir_info['group_gid']}")
    click.echo(f"Symbolic Mode    : {dir_info['symbolic_mode']}")
    click.echo(f"Octal Mode       : {dir_info['octal_mode']}")
    click.echo(f"User Permissions : {dir_info['user_permissions']}")
    click.echo(f"Group Permissions: {dir_info['group_permissions']}")
    click.echo(f"Others Permissions: {dir_info['others_permissions']}")

    # Now list contents
    click.secho("\nContents:", fg="cyan", bold=True)
    entries = list_directory_permissions(directory, recursive=recursive)
    if not entries:
        click.echo("  (Directory is empty)")
        return

    # Prepare a table: Path │ Octal │ Symbolic │ Owner UID │ Group GID │ Type
    table_data = []
    headers = ["Path (relative)", "Type", "Octal", "Symbolic", "Owner", "Group"]
    for info in entries:
        if "error" in info:
            # E.g. permission denied
            table_data.append([os.path.relpath(info["path"], directory), "?", "—", "—", "—", "—"])
            continue

        relpath = os.path.relpath(info["path"], directory)
        is_dir = os.path.isdir(info["path"])
        ftype = "dir" if is_dir else "file"
        table_data.append([
            relpath,
            ftype,
            info["octal_mode"],
            info["symbolic_mode"],
            info["owner_uid"],
            info["group_gid"]
        ])

        if verbose and is_dir and recursive:
            click.secho(f"[DEBUG] Re-entered: {info['path']}", fg="yellow")

    click.echo(tabulate(table_data, headers=headers, tablefmt="github"))


# --------------- Entry Point ---------------

if __name__ == "__main__":
    cli()

