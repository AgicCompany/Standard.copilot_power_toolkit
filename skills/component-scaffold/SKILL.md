---
name: component-scaffold
description: 'TRIGGER - read this BEFORE writing the first line of any new React component, and before creating any file under src/components/ or src/features/*/components/. Do NOT skip because the request looks like "just a small component" - that is precisely when conventions get silently dropped. Covers file layout, typed props, cn()-merged className, shadcn/ui composition, and the colocated Vitest + RTL test that is part of the definition of done. SKIP only when editing an existing component without changing its public API, or when the target is generated output under src/components/ui/ or src/generated/.'
---

# Component Scaffold

Produces a component that already matches the conventions in `react-ts.instructions.md`,
`shadcn-ui.instructions.md`, and `vitest-react-testing.instructions.md` — so review comments are
about behaviour, not layout.

## Decide placement first

| Scope | Location |
|---|---|
| Used by one feature | `src/features/<feature>/components/` |
| Used by 2+ features | `src/components/` |
| A shadcn/ui primitive | `src/components/ui/` — **install it, never hand-write it** |

A feature must never import from another feature's internals. If a second feature needs it, promote
it to `src/components/` in the same change.

## Component template

```tsx
// src/features/accounts/components/account-card.tsx
import { cn } from '@/lib/utils';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';

type AccountCardProps = {
  account: Account;
  onSelect?: (id: string) => void;
  className?: string;
};

export function AccountCard({ account, onSelect, className }: AccountCardProps) {
  return (
    <Card className={cn('transition-colors hover:bg-muted/50', className)}>
      <CardHeader>
        <CardTitle>{account.name}</CardTitle>
      </CardHeader>
      <CardContent>
        <Button variant="outline" onClick={() => onSelect?.(account.accountid)}>
          View details
        </Button>
      </CardContent>
    </Card>
  );
}
```

Rules encoded above:
- **Named export**, one component per file, in a kebab-case file: `AccountCard` → `account-card.tsx`
- **No `React.FC`** — it adds implicit children and buys nothing
- **`className` accepted and merged last via `cn()`** so callers can adjust spacing without new props
- **Semantic tokens** (`bg-muted`, `text-muted-foreground`), never raw palette colours — that is what
  makes dark mode work
- **Compose shadcn primitives**; don't edit `components/ui/**` for app-specific behaviour

## Test template

```tsx
// src/features/accounts/components/account-card.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AccountCard } from './account-card';

const account = { accountid: '1', name: 'Contoso' } as Account;

describe('AccountCard', () => {
  it('renders the account name', () => {
    render(<AccountCard account={account} />);
    expect(screen.getByText('Contoso')).toBeInTheDocument();
  });

  it('calls onSelect with the account id when activated', async () => {
    const onSelect = vi.fn();
    render(<AccountCard account={account} onSelect={onSelect} />);

    await userEvent.click(screen.getByRole('button', { name: /view details/i }));

    expect(onSelect).toHaveBeenCalledWith('1');
  });
});
```

Rules encoded above:
- **Query by role and accessible name** (`getByRole('button', { name: ... })`). This asserts the
  component is reachable by assistive tech as a side effect — a `getByTestId` test passes even when
  the control is unusable.
- **`userEvent`, not `fireEvent`** — it models real interaction (focus, key events, pointer).
- **Assert behaviour, not implementation.** No snapshot of the whole tree, no reaching into state.
- One `expect` per behaviour; the test name states the behaviour.

## If the component fetches data

It shouldn't. Put the query in a hook (`data-fetching.instructions.md`) and pass data in as props —
that keeps the component synchronously testable with no mock server. If a container component must
own the query, test the hook and the presentational component separately.

## If the component is a form

Use `react-hook-form` + Zod and the shadcn `Form`/`FormField`/`FormMessage` primitives — they wire
`htmlFor`, `aria-describedby`, and `aria-invalid` correctly, which hand-composed `Input` + `Label`
usually gets wrong. See `forms-and-validation.instructions.md`.

## Definition of done

- [ ] Correct folder for its actual scope
- [ ] Typed props, named export, `className` merged with `cn()`
- [ ] Semantic colour tokens only; verified in light *and* dark
- [ ] Interactive elements reachable by keyboard with a visible focus ring
- [ ] Colocated test querying by role, using `userEvent`
- [ ] No data fetching inside the component
