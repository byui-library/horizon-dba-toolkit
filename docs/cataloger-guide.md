# Working with the catalog through Codex

A guide for a cataloger who wants to ask questions of the Horizon database in
plain language, using OpenAI's Codex inside VS Code. You need to know MARC and
Horizon. You don't need to know SQL.

**What you get:** you describe what you want ("every record created on 26
October with ProQuest in a 590, with its title"), and Codex writes the query,
explains it, runs it against the live catalog, and hands back the answer or a
spreadsheet.

**What it cannot do:** change the catalog. Codex reads only. Deleting or
changing records stays a step you run yourself with Horizon's tools, after
review. See [What needs a person](#what-needs-a-person).

---

## One-time setup

About 30 minutes. Steps 1–3 may need IT if you cannot install software
yourself.

### 1. Know your two database identities

You reach the Horizon database two ways, and they are kept apart on purpose:

| Identity | Used by | Can it change data? |
| --- | --- | --- |
| Your **Windows login** | Codex, through `tools\Invoke-ReadOnlyQuery.ps1` | **No.** The tool switches to a read-only identity, `ro_query`, before every query. |
| Your **SQL login** | KillBib only, when **you** type it into the delete wrapper's prompt | Yes |

Codex never sees, asks for or uses the SQL login. If it ever asks for a
password, refuse and tell the maintainer.

There is no separate read-only *login* to remember. Instead, the moment the
query tool connects as you, it switches to a database identity, `ro_query`,
that SQL Server only lets read, and it cannot switch back. Any attempt to
change data is refused by the database itself. Every result starts with an
`Access:` line confirming it.

### 2. Install the software

| Install | Notes |
| --- | --- |
| **Git for Windows** | Downloads the toolkit and its updates. Accept the defaults. |
| **Visual Studio Code** | The editor Codex runs inside. |
| The **Codex** extension for VS Code | In VS Code: Extensions (the four-squares icon) → search "Codex" → choose the one published by **OpenAI** → Install. Sign in with your ChatGPT account. |

Windows PowerShell 5.1 is already on every Windows PC; nothing to install there.

### 3. Download the toolkit

In VS Code: **Terminal → New Terminal**, then paste:

```powershell
cd $HOME\Documents
git clone https://github.com/byui-library/horizon-dba-toolkit.git
```

Then **File → Open Folder…** and choose `Documents\horizon-dba-toolkit`.

### 4. Add your private files

The maintainer sends you a small private folder, by OneDrive or Teams, never by
the public repository. Copy two files from it into the toolkit's `tools`
folder:

| File | What it holds |
| --- | --- |
| `site.local.psd1` | Which server and database to connect to |
| `.redaction-denylist.txt` | Real names that must never be published. The test suite checks for them. |

Both are ignored by Git, so they never leave your computer. The same folder
holds a private handoff note for any job you are taking over.

### 5. Check it works

Open the Codex panel in VS Code and type:

> Run the tool tests, then run the access check, then count the rows in
> bib_control.

You should see `... passed, 0 failed`, an `Access:` line, and a count. If not,
see [Troubleshooting](#troubleshooting).

**Check the `Access:` line.** It must read:

```text
Access: read-only: the database itself refuses writes from <your login> as ro_query
```

If it says anything else, or the tool prints `STOPPED`, don't run queries.
Send the maintainer the message.

### 6. Keep Codex asking before it runs commands

In the Codex settings, keep the approval mode that **asks before running a
command**; don't switch to full auto. Approve a command when it runs
`tools\Invoke-ReadOnlyQuery.ps1`, `tools\Test-Tools.ps1` or
`tools\Build-SolutionDocs.ps1`. **Decline anything else that touches the
database**: `sqlcmd`, `Invoke-Sqlcmd`, a script that builds its own connection,
or any delete command. Its rules forbid those, so a request for one means
something has gone wrong. Tell the maintainer.

---

## Every time you start

1. **Get the latest version.** In the VS Code terminal:

   ```powershell
   git pull
   ```

   The maintainer keeps adding solutions and corrections; pulling first means
   Codex works from the current rules.

2. **Open the Codex panel and ask.** Codex reads this repository's
   [`AGENTS.md`](../AGENTS.md) automatically. That file tells it how to work
   with you and what it must never do.

### Good ways to ask

Be specific about the catalog. Codex works out the database side.

- "How many records were created by the account that loaded the ProQuest file,
  on 26 October 2026?"
- "List the bibs with more than one 245, with the 245s side by side. Save it as
  a spreadsheet."
- "For bib 5759566, show me every MARC field as stored."
- "Which ebook records have an EBC number in the 035 but no 856?"
- "Re-run the report from the 590-ebk-purchase-dda-report solution and save it."

Codex explains each query in a sentence or two before running it. If its
description doesn't match what you meant, say so before it runs.

### Where results go

Spreadsheets are saved under `excel reports\` inside the toolkit folder. Open
them in Excel directly. They are catalog data, so Git ignores them and they
never reach the public repository.

---

## What needs a person

| Task | Who |
| --- | --- |
| Questions, counts, lists, reports | **Codex**, any time |
| Reviewing a list of records before a delete | **You** |
| Running a delete (KillBib) | **You.** Codex prepares the exact command and checks the output; you type it. |
| Changing the toolkit itself (new solutions, fixes) | **The maintainer.** Codex can draft; you send the draft. |

**Deletes are permanent.** KillBib has no undo and no preview. The repository's
delete wrapper guards every step (it counts the list, asks you to type the
count, and can delete one trial record first), but it only protects you if the
list was right. Before any delete, read the solution's README with Codex, run
its audit queries, and review the list. The worked example is
[`solutions/590-proquest-ebc-batch-removal`](../solutions/590-proquest-ebc-batch-removal/README.md).

If a delete stops partway, **do not run it again from the start.** Paste the
output to Codex and to the maintainer. The output tells you how to resume, and
deciding that is a judgment call for a person.

---

## Troubleshooting

| You see | It means | Do this |
| --- | --- | --- |
| `cannot be loaded because running scripts is disabled` | Windows is blocking PowerShell scripts | Ask Codex to run it with `powershell -ExecutionPolicy Bypass -File ...`. That is the form `AGENTS.md` tells it to use. |
| `No site config at ...` | `site.local.psd1` is not in `tools\` | Repeat [step 4](#4-add-your-private-files). |
| `Login failed for user ...` | Your Windows login has no access to the database yet | Ask the maintainer to check which group grants database access. |
| `STOPPED - could not switch to the read-only user` | The read-only identity is missing, or you aren't allowed to use it | Nothing ran. Send the message to the maintainer. |
| `REFUSED - nothing was sent to the database` | The query tried to change something | Nothing happened. Codex should rewrite it as a read-only query. |
| Codex asks permission to run a command | Codex's own safety prompt | Read what it wants to run. Approve reads; never approve a delete command it proposes to run itself. |
| A title or note comes back blank | That field is over 255 characters and stored separately | Tell Codex: "long fields are in bib_longtext". The rules already say so, but it is worth the reminder. |

---

## For the maintainer

- The cataloger's local files: `tools\site.local.psd1` (template
  [`tools/site.local.example.psd1`](../tools/site.local.example.psd1)) and
  `tools\.redaction-denylist.txt`. Neither is tracked.
- Codex's rules: [`AGENTS.md`](../AGENTS.md). Claude Code's:
  [`CLAUDE.md`](../CLAUDE.md). Change them together.
- How reads are kept read-only, and the one-time `ro_query` setup:
  [`tools/README.md`, `Invoke-ReadOnlyQuery.ps1`](../tools/README.md#invoke-readonlyqueryps1).
  A `STOPPED ... could not switch` message on his machine means `ro_query` is
  missing, or the group he connects through has no `IMPERSONATE` grant on it.
- Nothing stops Codex from bypassing the script except its rules in
  `AGENTS.md` and the cataloger approving commands. That is why the guide asks
  him to keep command approval on.
