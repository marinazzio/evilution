---
name: create-issue
description: Create a beads issue and a matching GitHub issue, cross-linked via external-ref and description
argument-hint: "--title <title> --description <desc> --type <type> --priority <0-4>"
user-invocable: true
disable-model-invocation: true
---

# Create Cross-Linked Issue (Beads + GitHub)

Create a beads issue and a matching GitHub issue in Port-Royal/vanilla-mafia, with each linking to the other.

## Arguments

All arguments are passed as `$ARGUMENTS`. Parse them as bd-style flags:

- `--title` (required): Issue title
- `--description` (required): Why this issue exists and what needs to be done
- `--type` (required): `bug`, `feature`, or `task`
- `--priority` (required): 0-4 (0=critical, 4=backlog)
- `--parent` (optional): Parent beads issue ID for sub-tasks

Example:
```
/create-issue --title "Fix login redirect" --description "After login, users are redirected to /dashboard instead of the page they came from" --type bug --priority 1
```

## Steps

1. **Create the GitHub issue first** (to get the GH number):
   ```
   gh issue create --repo Port-Royal/vanilla-mafia --title "<title>" --body "<description>"
   ```
   Extract the issue number from the output.

2. **Create the beads issue** with `--external-ref gh-<number>`:
   ```
   bd create --title "<title>" --description "<description>\n\nGH: #<gh-number>" --type <type> --priority <priority> --external-ref gh-<number>
   ```
   Extract the beads issue ID from the output.

3. **Update the GitHub issue body** to include the beads ID:
   ```
   gh api repos/Port-Royal/vanilla-mafia/issues/<number> --method PATCH -f body="<description>

   Beads: <beads-id>"
   ```
   Use `gh api` (not `gh issue edit`) to avoid the Projects Classic GraphQL error.

4. **If `--parent` was provided**, set the parent on the beads issue:
   ```
   bd update <beads-id> --parent <parent-id>
   ```

5. **Display the result**: show both IDs in format `<beads-id> (GH #<number>)`.
