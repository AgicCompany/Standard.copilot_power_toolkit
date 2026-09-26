# Power Apps Code Apps — Full Reference

> Full reference backing `instructions/power-apps-code-apps.instructions.md`. That instruction file
> carries the rules Copilot applies while editing code; this document holds the long-form material —
> detailed Power Platform integration, the complete data-management and deployment sections, code
> quality guidelines, known limitations and workarounds, and the troubleshooting catalogue.
> 
> Read this when onboarding a data source, debugging a deployment, or hitting a platform limitation.
> It is deliberately NOT auto-loaded — it is ~670 lines.

---

# Power Apps Code Apps Development Instructions

Instructions for generating high-quality Power Apps Code Apps using TypeScript, React, and Power Platform SDK, following Microsoft's official best practices. Code Apps reached GA in February 2026.

## Project Context

- **Power Apps Code Apps**: Code-first web app development with Power Platform integration
- **TypeScript + React**: Recommended frontend stack with Vite bundler
- **Power Platform SDK**: @microsoft/power-apps (current version ^1.0.3) for connector integration
- **Power Apps CLI**: Power Platform CLI for project management and deployment
- **Port 3000**: Required for local development with Power Platform SDK
- **Power Apps Premium**: End-user licensing requirement for production use

## Development Standards

### Project Structure

- Use well-organized folder structure with clear separation of concerns:
  ```
  src/
  ├── components/          # Reusable UI components
  ├── hooks/              # Custom React hooks for Power Platform
  ├── generated/
  │   ├── services/       # Generated connector services (Power Apps CLI)
  │   └── models/         # Generated TypeScript models (Power Apps CLI)
  ├── utils/             # Utility functions and helpers
  ├── types/             # TypeScript type definitions
  ├── PowerProvider.tsx  # Power Platform context wrapper
  └── main.tsx          # Application entry point
  ```
- Keep generated files (`generated/services/`, `generated/models/`) separate from custom code
- Use consistent naming conventions (kebab-case for files, PascalCase for components)

### TypeScript Configuration

- Set `verbatimModuleSyntax: false` in tsconfig.json for Power Apps SDK compatibility
- Enable strict mode for type safety with recommended tsconfig.json:
  ```json
  {
    "compilerOptions": {
      "target": "ES2020",
      "useDefineForClassFields": true,
      "lib": ["ES2020", "DOM", "DOM.Iterable"],
      "module": "ESNext",
      "skipLibCheck": true,
      "verbatimModuleSyntax": false,
      "moduleResolution": "bundler",
      "allowImportingTsExtensions": true,
      "resolveJsonModule": true,
      "isolatedModules": true,
      "noEmit": true,
      "jsx": "react-jsx",
      "strict": true,
      "noUnusedLocals": true,
      "noUnusedParameters": true,
      "noFallthroughCasesInSwitch": true,
      // No "baseUrl" - TypeScript 6 reports it as error TS5101 (deprecated, removed in 7), which
      // fails `tsc -b` and so fails build-gate. A "paths" entry written as "./src/*" resolves
      // relative to this file without it.
      "paths": {
        "@/*": ["./src/*"]
      }
    }
  }
  ```
- Use proper typing for Power Platform connector responses
- Configure path alias with `"@": path.resolve(__dirname, "./src")` for cleaner imports
- Define interfaces for app-specific data structures
- Implement error boundaries and proper error handling types

### Advanced Power Platform Integration

#### Custom Control Frameworks (PCF Controls)
- **Integrate PCF controls**: Embed Power Apps Component Framework controls in Code Apps
  ```typescript
  // Example: Using custom PCF control for data visualization
  import { PCFControlWrapper } from './components/PCFControlWrapper';

  const MyComponent = () => {
    return (
      <PCFControlWrapper
        controlName="CustomChartControl"
        dataset={chartData}
        configuration={chartConfig}
      />
    );
  };
  ```
- **PCF control communication**: Handle events and data binding between PCF and React
- **Custom control deployment**: Package and deploy PCF controls with Code Apps

#### Power BI Embedded Analytics
- **Embed Power BI reports**: Integrate interactive dashboards and reports
  ```typescript
  import { PowerBIEmbed } from 'powerbi-client-react';

  const DashboardComponent = () => {
    return (
      <PowerBIEmbed
        embedConfig={{
          type: 'report',
          id: reportId,
          embedUrl: embedUrl,
          accessToken: accessToken,
          tokenType: models.TokenType.Aad,
          settings: {
            panes: { filters: { expanded: false, visible: false } }
          }
        }}
      />
    );
  };
  ```
- **Dynamic report filtering**: Filter Power BI reports based on Code App context
- **Report export functionality**: Enable PDF, Excel, and image exports

#### AI Builder Integration
- **Cognitive services integration**: Use AI Builder models for form processing, object detection
  ```typescript
  // Example: Document processing with AI Builder
  const processDocument = async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);

    const result = await AIBuilderService.ProcessDocument({
      modelId: 'document-processing-model-id',
      document: formData
    });

    return result.extractedFields;
  };
  ```
- **Prediction models**: Integrate custom AI models for business predictions
- **Sentiment analysis**: Analyze text sentiment using AI Builder
- **Object detection**: Implement image analysis and object recognition

#### Power Virtual Agents Integration
- **Chatbot embedding**: Integrate Power Virtual Agents bots within Code Apps
  ```typescript
  import { DirectLine } from 'botframework-directlinejs';
  import { WebChat } from 'botframework-webchat';

  const ChatbotComponent = () => {
    const directLine = new DirectLine({
      token: chatbotToken
    });

    return (
      <div style={{ height: '400px', width: '100%' }}>
        <WebChat directLine={directLine} />
      </div>
    );
  };
  ```
- **Context passing**: Share Code App context with chatbot conversations
- **Custom bot actions**: Trigger Code App functions from bot interactions
- Use generated TypeScript services from Power Apps CLI for connector operations
- Implement proper authentication flows with Microsoft Entra ID
- Handle connector consent dialogs and permission management
- PowerProvider implementation pattern (no SDK initialization required in v1.0):
  ```typescript
  import type { ReactNode } from "react";

  export default function PowerProvider({ children }: { children: ReactNode }) {
    return <>{children}</>;
  }
  ```
- Follow officially supported connector patterns:
  - SQL Server (including Azure SQL)
  - SharePoint
  - Office 365 Users/Groups
  - Azure Data Explorer
  - OneDrive for Business
  - Microsoft Teams
  - Dataverse (CRUD operations)

### React Patterns

- Use functional components with hooks for all new development
- Implement proper loading and error states for connector operations
- Consider Fluent UI React components (as used in official samples)
- Use React Query or SWR for data fetching and caching when appropriate
- Follow React best practices for component composition
- Implement responsive design with mobile-first approach
- Install key dependencies following official samples:
  - `@microsoft/power-apps` for Power Platform SDK
  - `@fluentui/react-components` for UI components
  - `concurrently` for parallel script execution (dev dependency)

### Data Management

- Store sensitive data in data sources, never in application code
- Use generated models for type-safe connector operations
- Implement proper data validation and sanitization
- Handle offline scenarios gracefully where possible
- Cache frequently accessed data appropriately

#### Data Fetching Hook Pattern

Wrap generated `*Service` calls in a hook that owns loading/error state, pagination, and retry —
don't call the service directly from component bodies. The generated `getAll()` accepts
`IGetAllOptions` (`select`, `filter`, `orderBy`, `top`, `skip`, `skipToken`, `maxPageSize`) — always
pass `select` to avoid over-fetching columns.

```typescript
// src/hooks/useAccounts.ts
import { useCallback, useEffect, useState } from 'react';
import { AccountsService } from '../generated/services/AccountsService';
import type { Accounts } from '../generated/models/AccountsModel';

interface UseAccountsResult {
  accounts: Accounts[];
  isLoading: boolean;
  error: Error | null;
  hasMore: boolean;
  loadMore: () => Promise<void>;
}

const MAX_RETRIES = 3;

// Dataverse throttles under sustained load (HTTP 429). Retry with backoff instead of
// surfacing a transient throttle as a user-facing error.
async function withRetry<T>(fn: () => Promise<T>, attempt = 0): Promise<T> {
  try {
    return await fn();
  } catch (err) {
    const status = (err as { response?: { status?: number } })?.response?.status;
    if (status === 429 && attempt < MAX_RETRIES) {
      await new Promise((resolve) => setTimeout(resolve, 2 ** attempt * 500));
      return withRetry(fn, attempt + 1);
    }
    throw err;
  }
}

export function useAccounts(): UseAccountsResult {
  const [accounts, setAccounts] = useState<Accounts[]>([]);
  const [skipToken, setSkipToken] = useState<string | undefined>(undefined);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchPage = useCallback(async (token?: string) => {
    setIsLoading(true);
    setError(null);
    try {
      const result = await withRetry(() =>
        AccountsService.getAll({
          select: ['name', 'accountnumber', 'address1_city'],
          top: 50,
          skipToken: token,
        })
      );
      setAccounts((prev) => (token ? [...prev, ...(result.data ?? [])] : result.data ?? []));
      setSkipToken(result.skipToken);
    } catch (err) {
      setError(err instanceof Error ? err : new Error('Failed to load accounts'));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPage();
  }, [fetchPage]);

  return {
    accounts,
    isLoading,
    error,
    hasMore: Boolean(skipToken),
    loadMore: () => fetchPage(skipToken),
  };
}
```

- Always pass `select` — fetching every column on a wide table is a common, easy-to-avoid performance mistake.
- Paginate with `skipToken`, not manual `skip` counting — Dataverse pages are cursor-based, not offset-based; `skip` doesn't behave the way SQL `OFFSET` does.
- Retry only on `429`. Don't blanket-retry every failure — a `400`/`403` retried 3 times just triples the wait before showing the user a real error.
- **Update semantics**: only send the fields that actually changed (`AccountsService.update(id, { name: newName })`, not the whole re-fetched record). Sending unchanged fields back can false-trigger Dataverse business logic/workflows and corrupt audit history — this is documented Dataverse behavior, not a hypothetical.
- Known current gaps in generated Dataverse services: no schema-change refresh (delete + re-add the data source instead), no FetchXML, no polymorphic lookups, no alternate keys. Don't spend time working around these as if they were bugs in your code.

#### Advanced Dataverse Relationships
- **Many-to-many relationships**: Implement junction tables and relationship services
  ```typescript
  // Example: User-to-Role many-to-many relationship
  const userRoles = await UserRoleService.getall();
  const filteredRoles = userRoles.filter(ur => ur.userId === currentUser.id);
  ```
- **Polymorphic lookups**: Handle customer fields that can reference multiple entity types
  ```typescript
  // Handle polymorphic customer lookup (Account or Contact)
  const customerType = record.customerType; // 'account' or 'contact'
  const customerId = record.customerId;
  const customer = customerType === 'account'
    ? await AccountService.get(customerId)
    : await ContactService.get(customerId);
  ```
- **Complex relationship queries**: Use $expand and $filter for efficient data retrieval
- **Relationship validation**: Implement business rules for relationship constraints

### Performance Optimization

- Use React.memo and useMemo for expensive computations
- Implement code splitting and lazy loading for large applications
- Optimize bundle size with tree shaking
- Use efficient connector query patterns to minimize API calls
- Implement proper pagination for large data sets

#### Offline-First Architecture with Sync Patterns
- **Service Worker implementation**: Enable offline functionality
  ```typescript
  // Example: Service worker registration
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js')
        .then(registration => console.log('SW registered:', registration))
        .catch(error => console.log('SW registration failed:', error));
    });
  }
  ```
- **Local data storage**: Use IndexedDB for offline data persistence
  ```typescript
  // Example: IndexedDB wrapper for offline storage
  class OfflineDataStore {
    async saveData(key: string, data: any) {
      const db = await this.openDB();
      const transaction = db.transaction(['data'], 'readwrite');
      transaction.objectStore('data').put({ id: key, data, timestamp: Date.now() });
    }

    async loadData(key: string) {
      const db = await this.openDB();
      const transaction = db.transaction(['data'], 'readonly');
      return transaction.objectStore('data').get(key);
    }
  }
  ```
- **Sync conflict resolution**: Handle data conflicts when coming back online
- **Background sync**: Implement periodic data synchronization
- **Progressive Web App (PWA)**: Enable app installation and offline capabilities

### Security Best Practices

- Never store secrets or sensitive configuration in code
- Use Power Platform's built-in authentication and authorization
- Implement proper input validation and sanitization
- Follow OWASP security guidelines for web applications
- Respect Power Platform data loss prevention policies
- Implement HTTPS-only communication

### Error Handling

- Implement comprehensive error boundaries in React
- Handle connector-specific errors gracefully
- Provide meaningful error messages to users
- Log errors appropriately without exposing sensitive information
- Implement retry logic for transient failures
- Handle network connectivity issues

### Testing Strategies

- Write unit tests for business logic and utilities
- Test React components with React Testing Library
- Mock Power Platform connectors in tests
- Implement integration tests for critical user flows
- Use TypeScript for better test safety
- Test error scenarios and edge cases

### Development Workflow

- Use Power Apps CLI for project initialization and connector management
- Follow git branching strategies appropriate for team size
- Implement proper code review processes
- Use linting and formatting tools (ESLint, Prettier)
- Configure development scripts using concurrently:
  - `"dev": "concurrently \"vite\" \"pa app run\""`
  - `"build": "tsc -b && vite build"`
- Implement automated testing in CI/CD pipelines
- Follow semantic versioning for releases

### Deployment and DevOps

- Use `pnpm build && pa app push` for deployment — `&&`, never `|`, or a failed build still pushes
  the previous bundle
- Implement proper environment management (dev, test, prod)
- Use environment-specific configuration files
- Implement blue-green or canary deployment strategies when possible
- Monitor application performance and errors in production
- Implement proper backup and disaster recovery procedures

#### Multi-Environment Deployment Pipelines
- **Environment-specific configurations**: Manage dev/test/staging/prod environments
  ```json
  // Example: environment-specific config files
  // config/development.json
  {
    "powerPlatform": {
      "environmentUrl": "https://dev-env.crm.dynamics.com",
      "apiVersion": "9.2"
    },
    "features": {
      "enableDebugMode": true,
      "enableAnalytics": false
    }
  }
  ```
- **Automated deployment pipelines**: Use Azure DevOps or GitHub Actions
  ```yaml
  # Example Azure DevOps pipeline step
  - task: PowerPlatformToolInstaller@2
  - task: PowerPlatformSetConnectionVariables@2
    inputs:
      authenticationType: 'PowerPlatformSPN'
      applicationId: '$(AppId)'
      clientSecret: '$(ClientSecret)'
      tenantId: '$(TenantId)'
  - task: PowerPlatformPublishCustomizations@2
  ```
- **Environment promotion**: Automated promotion from dev → test → staging → prod
- **Rollback strategies**: Implement automated rollback on deployment failures
- **Configuration management**: Use Azure Key Vault for environment-specific secrets

## Code Quality Guidelines

### Component Development

- Create reusable components with clear props interfaces
- Use composition over inheritance
- Implement proper prop validation with TypeScript
- Follow single responsibility principle
- Write self-documenting code with clear naming

### State Management

- Use React's built-in state management for simple scenarios
- Consider Redux Toolkit for complex state management
- Implement proper state normalization
- Avoid prop drilling with context or state management libraries
- Use derived state and computed values efficiently

### API Integration

- Use generated services from Power Apps CLI for consistency
- Implement proper request/response interceptors
- Handle authentication token management
- Implement request deduplication and caching
- Use proper HTTP status code handling

### Styling and UI

- Use consistent design system or component library
- Implement responsive design with CSS Grid/Flexbox
- Follow accessibility guidelines (WCAG 2.1)
- Use CSS-in-JS or CSS modules for component styling
- Implement dark mode support when appropriate
- Ensure mobile-friendly user interfaces

#### Advanced UI/UX Patterns

##### Design System Implementation with Component Libraries
- **Component library structure**: Build reusable component system
  ```typescript
  // Example: Design system button component
  interface ButtonProps {
    variant: 'primary' | 'secondary' | 'danger';
    size: 'small' | 'medium' | 'large';
    disabled?: boolean;
    onClick: () => void;
    children: React.ReactNode;
  }

  export const Button: React.FC<ButtonProps> = ({
    variant, size, disabled, onClick, children
  }) => {
    const classes = `btn btn-${variant} btn-${size} ${disabled ? 'btn-disabled' : ''}`;
    return <button className={classes} onClick={onClick} disabled={disabled}>{children}</button>;
  };
  ```
- **Design tokens**: Implement consistent spacing, colors, typography
- **Component documentation**: Use Storybook for component documentation

##### Dark Mode and Theming Systems
- **Theme provider implementation**: Support multiple themes
  ```typescript
  // Example: Theme context and provider
  const ThemeContext = createContext({
    theme: 'light',
    toggleTheme: () => {}
  });

  export const ThemeProvider: React.FC<{children: ReactNode}> = ({ children }) => {
    const [theme, setTheme] = useState<'light' | 'dark'>('light');

    const toggleTheme = () => {
      setTheme(prev => prev === 'light' ? 'dark' : 'light');
    };

    return (
      <ThemeContext.Provider value={{ theme, toggleTheme }}>
        <div className={`theme-${theme}`}>{children}</div>
      </ThemeContext.Provider>
    );
  };
  ```
- **CSS custom properties**: Use CSS variables for dynamic theming
- **System preference detection**: Respect user's OS theme preference

##### Responsive Design Advanced Patterns
- **Container queries**: Use container-based responsive design
  ```css
  /* Example: Container query for responsive components */
  .card-container {
    container-type: inline-size;
  }

  @container (min-width: 400px) {
    .card {
      display: grid;
      grid-template-columns: 1fr 1fr;
    }
  }
  ```
- **Fluid typography**: Implement responsive font scaling
- **Adaptive layouts**: Change layout patterns based on screen size and context

##### Animation and Micro-interactions
- **Framer Motion integration**: Smooth animations and transitions
  ```typescript
  import { motion, AnimatePresence } from 'framer-motion';

  const AnimatedCard = () => {
    return (
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -20 }}
        transition={{ duration: 0.3 }}
        whileHover={{ scale: 1.02 }}
        className="card"
      >
        Card content
      </motion.div>
    );
  };
  ```
- **Loading states**: Animated skeletons and progress indicators
- **Gesture recognition**: Swipe, pinch, and touch interactions
- **Performance optimization**: Use CSS transforms and will-change property

##### Accessibility Automation and Testing
- **ARIA implementation**: Proper semantic markup and ARIA attributes
  ```typescript
  // Example: Accessible modal component
  const Modal: React.FC<{isOpen: boolean, onClose: () => void, children: ReactNode}> = ({
    isOpen, onClose, children
  }) => {
    useEffect(() => {
      if (isOpen) {
        document.body.style.overflow = 'hidden';
        const focusableElement = document.querySelector('[data-autofocus]') as HTMLElement;
        focusableElement?.focus();
      }
      return () => { document.body.style.overflow = 'unset'; };
    }, [isOpen]);

    return (
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="modal-title"
        className={isOpen ? 'modal-open' : 'modal-hidden'}
      >
        {children}
      </div>
    );
  };
  ```
- **Automated accessibility testing**: Integrate axe-core for accessibility testing
- **Keyboard navigation**: Implement full keyboard accessibility
- **Screen reader optimization**: Test with NVDA, JAWS, and VoiceOver

##### Internationalization (i18n) and Localization
- **React-intl integration**: Multi-language support
  ```typescript
  import { FormattedMessage, useIntl } from 'react-intl';

  const WelcomeMessage = ({ userName }: { userName: string }) => {
    const intl = useIntl();

    return (
      <h1>
        <FormattedMessage
          id="welcome.title"
          defaultMessage="Welcome, {userName}!"
          values={{ userName }}
        />
      </h1>
    );
  };
  ```
- **Language detection**: Automatic language detection and switching
- **RTL support**: Right-to-left language support for Arabic, Hebrew
- **Date and number formatting**: Locale-specific formatting
- **Translation management**: Integration with translation services

## Current Limitations and Workarounds

### Known Limitations

- Content Security Policy (CSP) not yet supported
- Storage SAS IP restrictions not supported
- No Power Platform Git integration
- Dataverse solutions supported, but solution packager and source code integration are limited
- Application Insights supported through SDK logger configuration (no built-in native integration)

### Workarounds

- Use alternative error tracking solutions if needed
- Implement manual deployment workflows
- Use external tools for advanced analytics
- Plan for future migration to supported features

## Documentation Standards

- Maintain comprehensive README.md with setup instructions
- Document all custom components and hooks
- Include troubleshooting guides for common issues
- Document deployment procedures and requirements
- Maintain changelog for version updates
- Include architectural decision records for major choices

## Troubleshooting Common Issues

### Development Issues

- **Port 3000 conflicts**: Kill existing processes with `netstat -ano | findstr :3000` then `taskkill /PID {PID} /F`
- **Authentication failures**: Verify environment setup and user permissions with `pa auth status`
- **Package installation failures**: Clear npm cache with `npm cache clean --force` and reinstall
- **TypeScript compilation errors**: Check verbatimModuleSyntax setting and SDK compatibility
- **Connector permission errors**: Ensure proper consent flow and admin permissions
- **PowerProvider issues**: Ensure v1.0 apps do not wait on SDK initialization
- **Vite dev server issues**: Ensure host and port configuration match requirements

### Deployment Issues

- **Build failures**: Verify all dependencies with `npm audit` and check build configuration
- **Authentication errors**: Re-authenticate Power Apps CLI with `pa auth logout` then `pa auth login`
- **Connector unavailable**: Verify connector setup in Power Platform and connection status
- **Performance issues**: Optimize bundle size with `pnpm build --report` and implement caching
- **Environment mismatch**: Check the `environmentId` in `power.config.json` against the environment you mean
- **App timeout errors**: Check build output and network connectivity

### Runtime Issues

- **"App timed out" errors**: Verify `pnpm build` was executed and the deployment output is valid
- **Connector authentication prompts**: Ensure proper consent flow implementation
- **Data loading failures**: Check network requests and connector permissions
- **UI rendering issues**: Verify Fluent UI compatibility and responsive design implementation

## Best Practices Summary

1. **Follow Microsoft's official documentation and best practices**
2. **Use TypeScript for type safety and better developer experience**
3. **Implement proper error handling and user feedback**
4. **Optimize for performance and user experience**
5. **Follow security best practices and Power Platform policies**
6. **Write maintainable, testable, and well-documented code**
7. **Use generated services and models from Power Apps CLI**
8. **Plan for future feature updates and migrations**
9. **Implement comprehensive testing strategies**

10. **Follow proper DevOps and deployment practices**
