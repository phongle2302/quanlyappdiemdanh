using System.Threading.RateLimiting;
using Attendance.Api;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);
Directory.CreateDirectory("App_Data");
builder.Configuration.AddJsonFile("App_Data/smtp.local.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();
if (args.Length > 0) builder.Configuration.AddCommandLine(args);
builder.Services.AddDbContext<AppDb>(o => o.UseSqlite(builder.Configuration.GetConnectionString("Database") ?? "Data Source=App_Data/attendance.db"));
builder.Services.AddSingleton<PasswordHasher<User>>();
builder.Services.AddSingleton<Mailer>();
builder.Services.AddAuthentication("token").AddScheme<AuthenticationSchemeOptions, TokenAuthentication>("token", _ => { });
builder.Services.AddAuthorization(o =>
{
    o.AddPolicy("admin", p => p.RequireRole("admin"));
    o.AddPolicy("staff", p => p.RequireRole("admin", "teacher"));
    o.AddPolicy("student", p => p.RequireRole("student"));
});
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = 429;
    o.OnRejected = async (c, ct) => await c.HttpContext.Response.WriteAsJsonAsync(new { message = "Quá nhiều yêu cầu. Thử lại sau một phút." }, ct);
    o.AddPolicy("auth", context => RateLimitPartition.GetFixedWindowLimiter(context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 20, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
});
var app = builder.Build();
Directory.CreateDirectory("App_Data");
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDb>();
    await db.Database.EnsureCreatedAsync();
    var password = builder.Configuration["Bootstrap:AdminPassword"];
    if (!await db.Users.AnyAsync(x => x.Role == "admin") && !string.IsNullOrEmpty(password))
    {
        if (!Security.ValidPassword(password)) throw new InvalidOperationException("Bootstrap:AdminPassword không đủ mạnh.");
        var email = builder.Configuration["Bootstrap:AdminEmail"]?.Trim().ToLowerInvariant();
        if (!Security.ValidEmail(email)) throw new InvalidOperationException("Cần Bootstrap:AdminEmail hợp lệ.");
        var username = builder.Configuration["Bootstrap:AdminUsername"]?.Trim().ToLowerInvariant() ?? "admin";
        if (!Security.ValidUsername(username)) throw new InvalidOperationException("Bootstrap:AdminUsername không hợp lệ.");
        var u = new User { Username = username, Email = email!, Name = "Quản trị viên", Role = "admin", Verified = true };
        u.PasswordHash = scope.ServiceProvider.GetRequiredService<PasswordHasher<User>>().HashPassword(u, password);
        db.Users.Add(u); await db.SaveChangesAsync();
    }
}
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers.CacheControl = "no-store";
    try { await next(context); }
    catch (BadHttpRequestException e) when (!context.Response.HasStarted)
    {
        context.Response.StatusCode = e.StatusCode;
        await context.Response.WriteAsJsonAsync(new { message = "Dữ liệu yêu cầu không hợp lệ." });
    }
    catch (DbUpdateException e) when (e.InnerException is Microsoft.Data.Sqlite.SqliteException { SqliteErrorCode: 19 })
    {
        context.Response.StatusCode = 409; await context.Response.WriteAsJsonAsync(new { message = "Dữ liệu trùng lặp hoặc đang được sử dụng." });
    }
    catch (Exception e) when (e is not OperationCanceledException && !context.Response.HasStarted)
    {
        app.Logger.LogError(e, "Request failed: {Path}", context.Request.Path);
        context.Response.StatusCode = 500; await context.Response.WriteAsJsonAsync(new { message = "Không thể xử lý yêu cầu. Kiểm tra cấu hình máy chủ hoặc thử lại." });
    }
});
if (!app.Environment.IsDevelopment()) { app.UseHsts(); app.UseHttpsRedirection(); }
app.UseRateLimiter(); app.UseAuthentication(); app.UseAuthorization();
app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "Attendly API" }));
app.MapAuth(); app.MapManagement(); app.MapAttendance();
app.Run();
