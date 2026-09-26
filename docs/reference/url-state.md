# URL State — Implementation Detail

Loaded on demand. The rule itself is in `instructions/react-ts.instructions.md`: if a user would
reasonably expect to share, bookmark or return to a view, its state belongs in the URL.

## The four things `useState` silently costs you

Nothing fails loudly, which is why this is easy to miss in review:

1. Sharing a link to what you are looking at
2. Bookmarking it
3. The back button undoing a filter
4. A refresh keeping your place

Users do not report these. They conclude the app is awkward.

## Debounced input — the exception worth knowing

Keep the *typing* in local state; push only the *debounced* value to the URL. Otherwise every
keystroke becomes a history entry and the back button walks through the search term letter by letter.

```tsx
const [params, setParams] = useSearchParams();
const [typed, setTyped] = useState(params.get('q') ?? '');
const debounced = useDebouncedValue(typed, 300);

useEffect(() => {
  setParams(
    (prev) => {
      const next = new URLSearchParams(prev);
      debounced ? next.set('q', debounced) : next.delete('q');
      next.set('page', '0');           // a new search starts at the first page
      return next;
    },
    { replace: true },
  );
}, [debounced, setParams]);
```

This is the one place the mirror rule bends, and only for the in-flight keystrokes.

## `replace` vs `push`

- **`{ replace: true }` for filter and search changes.** Twelve filter tweaks should not mean twelve
  back presses to leave the page.
- **Push for navigation the user would call a "step"** — opening a record, moving to the next page of
  results if that is how your users think about it.

## Parse, do not trust

A URL is user-editable input. `?page=banana` and `?page=-1` both reach your code, and an unbounded or
negative `skip` reaches the server.

```ts
const listParams = z.object({
  q: z.string().trim().max(200).default(''),
  page: z.coerce.number().int().min(0).max(10_000).catch(0),
});

const { q, page } = listParams.parse(Object.fromEntries(params));
```

`.catch(0)` rather than `.default(0)` — `default` only fills a *missing* value, while `catch` also
absorbs a present-but-invalid one, which is the case that actually occurs.

## Clearing, not emptying

Delete the key rather than setting it empty. `?q=&page=0` is noise in every shared link, and
`params.get('q')` returning `''` versus `null` is a distinction someone will eventually branch on.

## Power Apps Code Apps

The app runs in an iframe inside the Power Platform shell, so the address bar the user sees is the
**host's**, not yours. Deep links still work for in-app navigation and the back button behaves, but a
URL copied from the browser will not reproduce a filtered view for a colleague.

Use URL state anyway — refresh-survival, back-button behaviour and having one source of truth are
worth it on their own — but do not promise users shareable links without testing it in the published
app first.
