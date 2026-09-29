---
name: appinsights-instrumentation
description: Automates the integration of Azure Application Insights telemetry into web applications for monitoring, diagnostics, and performance tracking
---

# Application Insights Instrumentation

This skill helps you integrate Azure Application Insights into your applications for comprehensive monitoring and telemetry.

## First: which runtime is this? The SDKs are not interchangeable

**Answer this before writing any code.** Picking the wrong package produces something that compiles,
lints, builds, and never sends a single telemetry event.

| Runtime | Package | Section |
|---|---|---|
| ASP.NET Core | `Microsoft.ApplicationInsights.AspNetCore` | [ASP.NET Core](#for-aspnet-core-applications) |
| Node.js — server, API, function | `applicationinsights` | [Node.js](#for-nodejs-applications) |
| **Browser — React/Vite SPA, Power Apps Code App** | **`@microsoft/applicationinsights-web`** | [Browser](#for-browser-applications-react--vite--power-apps-code-apps) |

**A Power Apps Code App is always the browser row.** It is a client-only React SPA with no server of
its own. The Node `applicationinsights` package cannot run there at all — it reads `process.env`,
which does not exist in a browser, and writes a disk cache for offline telemetry. `import`ing it into
a Vite bundle either fails to resolve Node builtins or silently no-ops.

## When to Use This Skill

Use this skill when you need to:
- Add monitoring and telemetry to ASP.NET Core applications
- Instrument Node.js applications with Application Insights
- **Add error and usage telemetry to a browser SPA, including a Power Apps Code App**
- Configure custom metrics and logging
- Set up performance tracking and dependency monitoring
- Implement application health monitoring

## Capabilities

- Instrument ASP.NET Core applications with Application Insights SDK
- Configure telemetry for Node.js applications
- Set up custom metrics and logging
- Configure connection strings and instrumentation keys
- Enable dependency tracking and request monitoring
- Implement custom telemetry tracking

## Prerequisites

- Azure subscription with Application Insights resource
- Target application (ASP.NET Core or Node.js)
- Application hosted in Azure (App Service, Container Apps, etc.) or on-premises
- Understanding of your application's monitoring requirements

## Implementation Guide

### For ASP.NET Core Applications

**Step 1: Add the NuGet Package**

```bash
dotnet add package Microsoft.ApplicationInsights.AspNetCore
```

**Step 2: Configure in Program.cs**

```csharp
// In Program.cs (ASP.NET Core 6+)
var builder = WebApplication.CreateBuilder(args);

// Add Application Insights telemetry
builder.Services.AddApplicationInsightsTelemetry(options =>
{
    options.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
});

var app = builder.Build();
```

**Step 3: Add Configuration**

Add to `appsettings.json`:

```json
{
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=your-key;IngestionEndpoint=https://your-region.in.applicationinsights.azure.com/"
  },
  "Logging": {
    "ApplicationInsights": {
      "LogLevel": {
        "Default": "Information",
        "Microsoft": "Warning"
      }
    }
  }
}
```

**Step 4: Use Custom Telemetry**

```csharp
public class MyService
{
    private readonly TelemetryClient _telemetryClient;
    
    public MyService(TelemetryClient telemetryClient)
    {
        _telemetryClient = telemetryClient;
    }
    
    public async Task ProcessOrderAsync(Order order)
    {
        using var operation = _telemetryClient.StartOperation<RequestTelemetry>("ProcessOrder");
        
        try
        {
            // Track custom event
            _telemetryClient.TrackEvent("OrderProcessing", new Dictionary<string, string>
            {
                { "OrderId", order.Id },
                { "CustomerId", order.CustomerId }
            });
            
            // Your business logic here
            await ProcessOrder(order);
            
            // Track custom metric
            _telemetryClient.TrackMetric("OrderValue", order.TotalAmount);
            
            operation.Telemetry.Success = true;
        }
        catch (Exception ex)
        {
            _telemetryClient.TrackException(ex);
            operation.Telemetry.Success = false;
            throw;
        }
    }
}
```

### For Node.js Applications

**Step 1: Install Package**

```bash
npm install applicationinsights
```

**Step 2: Initialize at Startup**

```javascript
// At the very beginning of your app (before other requires)
const appInsights = require('applicationinsights');

appInsights.setup(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING)
    .setAutoDependencyCorrelation(true)
    .setAutoCollectRequests(true)
    .setAutoCollectPerformance(true, true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectConsole(true)
    .setUseDiskRetryCaching(true)
    .setSendLiveMetrics(true)
    .start();

const client = appInsights.defaultClient;

module.exports = client;
```

**Step 3: Track Custom Telemetry**

```javascript
const appInsights = require('./appInsights');

async function processOrder(order) {
    const startTime = Date.now();
    
    try {
        // Track custom event
        appInsights.trackEvent({
            name: 'OrderProcessing',
            properties: {
                orderId: order.id,
                customerId: order.customerId
            }
        });
        
        // Your business logic
        await handleOrder(order);
        
        // Track metric
        const duration = Date.now() - startTime;
        appInsights.trackMetric({ name: 'OrderProcessingTime', value: duration });
        
        // Track custom metric
        appInsights.trackMetric({ name: 'OrderValue', value: order.totalAmount });
        
    } catch (error) {
        // Track exception
        appInsights.trackException({ exception: error });
        throw error;
    }
}
```

### For Browser Applications (React / Vite / Power Apps Code Apps)

```bash
pnpm add @microsoft/applicationinsights-web
```

```ts
// src/lib/app-insights.ts
import { ApplicationInsights } from '@microsoft/applicationinsights-web';

const connectionString = import.meta.env.VITE_APPLICATIONINSIGHTS_CONNECTION_STRING;

export const appInsights = new ApplicationInsights({
  config: {
    connectionString,
    enableAutoRouteTracking: true,       // SPA route changes are not page loads
    enableUnhandledPromiseRejectionTracking: true,
    disableFetchTracking: false,
  },
});

if (connectionString) {
  appInsights.loadAppInsights();
  appInsights.trackPageView();
}
```

Import it once from `main.tsx` for the side effect. Guard on the connection string being present so
a developer without one gets a working app rather than a crash on boot.

**The connection string is public and belongs in a `VITE_` variable.** It is an ingestion-only
endpoint: it grants write access to your telemetry and no read access to anything. This is the one
category of `VITE_` value that is *supposed* to ship in the bundle.

`vite-env-guard` matches on `CONNECTION_STRING` and will block it once a real value is present in an
`.env` file. **The fix is `VITE_ENV_GUARD_ALLOW`, naming the variable exactly — never rename the
variable until the guard stops firing.** See `hooks/vite-env-guard.README.md`.

Two SPA-specific points that do not arise server-side:

- **Route changes are not page loads.** Without `enableAutoRouteTracking`, a SPA reports one page
  view per session and your usage data is meaningless.
- **Wire it to your error boundary and your query client.** Automatic collection catches unhandled
  errors and rejections; it does not catch an error a React error boundary has already caught, nor a
  TanStack Query failure that resolved into an error state. Report those explicitly via
  `trackException`.

**Code Apps specifically:** CSP is not supported for Code Apps, so there is nothing to allowlist — but
telemetry is loaded inside the Power Apps iframe, so verify events actually arrive in the portal-hosted
app, not only in a local run.

## Best Practices

### Security
- **Never hardcode connection strings** - Use environment variables or Azure Key Vault
- **The browser is the exception** - an Application Insights connection string is ingestion-only and
  must ship in the bundle for client-side telemetry to work at all. Do not route it through a
  server proxy or Key Vault "to be safe"; that adds a hop and protects nothing.
- **Use Managed Identity** when running in Azure for authentication
- **Rotate instrumentation keys** regularly if not using connection strings
- **Filter sensitive data** before sending telemetry
- **Implement least-privilege access** to Application Insights resources

### Performance
- **Enable sampling** in high-volume applications to control costs:
  ```csharp
  builder.Services.AddApplicationInsightsTelemetry(options =>
  {
      options.EnableAdaptiveSampling = true;
  });
  ```
- **Use async methods** for telemetry operations
- **Batch telemetry** when tracking multiple events
- **Configure appropriate flush intervals**

### Monitoring
- **Set up custom properties** for better filtering:
  ```csharp
  var telemetryInitializer = new CustomTelemetryInitializer();
  builder.Services.AddSingleton<ITelemetryInitializer>(telemetryInitializer);
  ```
- **Create custom metrics** for business KPIs
- **Configure alerts** in Azure Portal for critical patterns
- **Use dependency tracking** to identify bottlenecks
- **Enable live metrics** for real-time monitoring

### Cost Management
- **Use sampling** to reduce ingestion volume (90-95% reduction typical)
- **Filter noisy telemetry** at source
- **Set retention policies** appropriate to your needs
- **Monitor ingestion rates** and costs in Azure Portal

## Common Patterns

### Pattern 1: Track Business Metrics

```csharp
public class OrderMetricsTracker
{
    private readonly TelemetryClient _telemetry;
    
    public void TrackOrderCompleted(Order order)
    {
        _telemetry.TrackEvent("OrderCompleted", new Dictionary<string, string>
        {
            { "OrderId", order.Id },
            { "PaymentMethod", order.PaymentMethod },
            { "ShippingCountry", order.ShippingAddress.Country }
        });
        
        _telemetry.TrackMetric("OrderRevenue", order.TotalAmount);
        _telemetry.TrackMetric("OrderItems", order.Items.Count);
    }
}
```

### Pattern 2: Track User Actions

```javascript
function trackUserAction(action, details) {
    appInsights.trackEvent({
        name: `User_${action}`,
        properties: {
            userId: details.userId,
            action: action,
            page: details.page,
            timestamp: new Date().toISOString()
        }
    });
}
```

### Pattern 3: Performance Monitoring

```csharp
public async Task<Result> PerformOperationAsync()
{
    using var operation = _telemetryClient.StartOperation<DependencyTelemetry>("DatabaseQuery");
    operation.Telemetry.Type = "SQL";
    operation.Telemetry.Target = "ProductionDB";
    
    try
    {
        var result = await _database.QueryAsync();
        operation.Telemetry.Success = true;
        return result;
    }
    catch (Exception ex)
    {
        operation.Telemetry.Success = false;
        _telemetryClient.TrackException(ex);
        throw;
    }
}
```

## Troubleshooting

### Telemetry Not Appearing

1. **Verify connection string** is correct and accessible
2. **Check network connectivity** to Azure ingestion endpoint
3. **Ensure TelemetryClient.Flush()** is called before app shutdown
4. **Check sampling configuration** - you might be filtering too aggressively
5. **Verify no firewall** blocking outbound connections to Azure
6. **Wait 2-3 minutes** for telemetry to appear in portal

### High Costs

1. **Enable adaptive sampling** to reduce volume
2. **Filter unnecessary telemetry** at the source
3. **Review and adjust** data retention policies
4. **Use summary metrics** instead of detailed events where possible

### Missing Dependencies

1. **Verify dependency tracking is enabled** in configuration
2. **Check that packages** support automatic instrumentation
3. **Manually track dependencies** if auto-collection doesn't work

## Environment Configuration

### Development

```json
{
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=dev-key",
    "EnableAdaptiveSampling": false,
    "EnableDebugLogger": true
  }
}
```

### Production

```json
{
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=prod-key",
    "EnableAdaptiveSampling": true,
    "SamplingPercentage": 5.0
  }
}
```

## References

- [Application Insights Overview](https://docs.microsoft.com/azure/azure-monitor/app/app-insights-overview)
- [ASP.NET Core Integration](https://docs.microsoft.com/azure/azure-monitor/app/asp-net-core)
- [Node.js Integration](https://docs.microsoft.com/azure/azure-monitor/app/nodejs)
- [Sampling in Application Insights](https://docs.microsoft.com/azure/azure-monitor/app/sampling)
- [Custom Events and Metrics](https://docs.microsoft.com/azure/azure-monitor/app/api-custom-events-metrics)
