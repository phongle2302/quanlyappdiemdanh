using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using static Attendance.Api.AuthEndpoints;

namespace Attendance.Api;

public static class ManagementEndpoints
{
    public static Task<bool> CanManage(AppDb db, ClaimsPrincipal p, Guid id) => p.Admin() ? Task.FromResult(true)
        : db.Courses.AnyAsync(x => x.Id == id && x.TeacherId == p.UserId());
    public static IQueryable<Course> VisibleCourses(AppDb db, ClaimsPrincipal p) => p.Admin() ? db.Courses
        : p.IsInRole("teacher") ? db.Courses.Where(x => x.TeacherId == p.UserId())
        : db.Courses.Where(x => db.Enrollments.Any(e => e.CourseId == x.Id && e.StudentId == p.UserId()));

    public static void MapManagement(this WebApplication app)
    {
        var users = app.MapGroup("/api/users").RequireAuthorization("admin");
        users.MapGet("/", async (AppDb db) => Results.Ok((await db.Users.OrderBy(x => x.Name).ToListAsync()).Select(x => x.Public())));
        users.MapPost("/", async (UserInput i, AppDb db, ClaimsPrincipal p, PasswordHasher<User> h) =>
        {
            if (!ValidUser(i) || !Security.ValidPassword(i.Password)) return Error("Thông tin không hợp lệ; mật khẩu cần 10–128 ký tự, chữ hoa, thường và số.");
            var username = i.Username.Trim().ToLowerInvariant(); var email = i.Email.Trim().ToLowerInvariant();
            if (await db.Users.AnyAsync(x => x.Username == username || x.Email == email)) return Error("Tên đăng nhập hoặc email đã tồn tại.", 409);
            var u = new User { Username = username, Email = email, Name = i.Name.Trim(), Role = i.Role, Verified = true };
            u.PasswordHash = h.HashPassword(u, i.Password!); db.Users.Add(u); Security.Audit(db, p, "user.create", u.Id);
            await db.SaveChangesAsync(); return Results.Created($"/api/users/{u.Id}", u.Public());
        });
        users.MapPut("/{id:guid}", async (Guid id, UserInput i, AppDb db, ClaimsPrincipal p, PasswordHasher<User> h) =>
        {
            var u = await db.Users.FindAsync(id);
            if (u is null) return Error("Không tìm thấy tài khoản.", 404);
            if (!ValidUser(i) || (!string.IsNullOrEmpty(i.Password) && !Security.ValidPassword(i.Password))) return Error("Thông tin tài khoản không hợp lệ.");
            if (id == p.UserId() && i.Role != "admin") return Error("Không thể tự hạ quyền quản trị.");
            if (u.Role == "teacher" && i.Role != "teacher" && await db.Courses.AnyAsync(x => x.TeacherId == id)) return Error("Chuyển các lớp sang giáo viên khác trước khi đổi vai trò.");
            if (u.Role == "student" && i.Role != "student" && await db.Enrollments.AnyAsync(x => x.StudentId == id)) return Error("Xóa sinh viên khỏi các lớp trước khi đổi vai trò.");
            var username = i.Username.Trim().ToLowerInvariant(); var email = i.Email.Trim().ToLowerInvariant();
            if (await db.Users.AnyAsync(x => x.Id != id && (x.Username == username || x.Email == email))) return Error("Tên đăng nhập hoặc email đã tồn tại.", 409);
            u.Username = username; u.Email = email; u.Name = i.Name.Trim(); u.Role = i.Role;
            if (!string.IsNullOrEmpty(i.Password)) u.PasswordHash = h.HashPassword(u, i.Password);
            await db.LoginSessions.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.OtpChallenges.Where(x => x.UserId == id).ExecuteDeleteAsync();
            Security.Audit(db, p, "user.update", id); await db.SaveChangesAsync(); return Results.Ok(u.Public());
        });
        users.MapDelete("/{id:guid}", async (Guid id, AppDb db, ClaimsPrincipal p) =>
        {
            if (id == p.UserId()) return Error("Không thể xóa tài khoản đang sử dụng.");
            if (await db.Courses.AnyAsync(x => x.TeacherId == id)) return Error("Chuyển các lớp sang giáo viên khác trước khi xóa.");
            var u = await db.Users.FindAsync(id); if (u is null) return Error("Không tìm thấy tài khoản.", 404);
            db.Users.Remove(u); Security.Audit(db, p, "user.delete", id); await db.SaveChangesAsync(); return Results.NoContent();
        });
        app.MapGet("/api/audit", async (AppDb db) => Results.Ok(await db.AuditEntries.OrderByDescending(x => x.Id).Take(200).ToListAsync())).RequireAuthorization("admin");
        var courses = app.MapGroup("/api/courses").RequireAuthorization();
        courses.MapGet("/", async (AppDb db, ClaimsPrincipal p) =>
        {
            var list = await VisibleCourses(db, p).OrderBy(x => x.Code).ToListAsync();
            return p.IsInRole("student")
                ? Results.Ok(list.Select(c => new { c.Id, c.Code, c.Name, c.Room, c.TeacherId }))
                : Results.Ok((object)list);
        });
        courses.MapPost("/", async (CourseInput i, AppDb db, ClaimsPrincipal p) =>
        {
            if (!p.Admin() && i.TeacherId != p.UserId()) return Results.Forbid();
            if (!await ValidCourse(db, i)) return Error("Kiểm tra mã lớp, tên lớp, phòng và tài khoản giáo viên.");
            if (await db.Courses.AnyAsync(x => x.Code == i.Code.Trim().ToUpperInvariant())) return Error("Mã lớp đã tồn tại.", 409);
            var c = new Course(); ApplyCourse(c, i); db.Courses.Add(c); Security.Audit(db, p, "course.create", c.Id);
            await db.SaveChangesAsync(); return Results.Created($"/api/courses/{c.Id}", c);
        }).RequireAuthorization("staff");
        courses.MapPut("/{id:guid}", async (Guid id, CourseInput i, AppDb db, ClaimsPrincipal p) =>
        {
            var c = await db.Courses.FindAsync(id); if (c is null) return Error("Không tìm thấy lớp.", 404);
            if (!await CanManage(db, p, id) || (!p.Admin() && i.TeacherId != p.UserId())) return Results.Forbid();
            if (!await ValidCourse(db, i)) return Error("Thông tin lớp không hợp lệ.");
            if (await db.Courses.AnyAsync(x => x.Id != id && x.Code == i.Code.Trim().ToUpperInvariant())) return Error("Mã lớp đã tồn tại.", 409);
            ApplyCourse(c, i); Security.Audit(db, p, "course.update", id); await db.SaveChangesAsync(); return Results.Ok(c);
        }).RequireAuthorization("staff");
        courses.MapDelete("/{id:guid}", async (Guid id, AppDb db, ClaimsPrincipal p) =>
        {
            var c = await db.Courses.FindAsync(id); if (c is null) return Error("Không tìm thấy lớp.", 404);
            if (!await CanManage(db, p, id)) return Results.Forbid();
            db.Courses.Remove(c); Security.Audit(db, p, "course.delete", id); await db.SaveChangesAsync(); return Results.NoContent();
        }).RequireAuthorization("staff");
        courses.MapGet("/{id:guid}/students", async (Guid id, AppDb db, ClaimsPrincipal p) =>
        {
            if (!await CanManage(db, p, id)) return Results.Forbid();
            var list = await db.Users.Where(x => db.Enrollments.Any(e => e.CourseId == id && e.StudentId == x.Id)).ToListAsync();
            return Results.Ok(list.Select(x => x.Public()));
        }).RequireAuthorization("staff");
        courses.MapGet("/{id:guid}/candidates", async (Guid id, AppDb db, ClaimsPrincipal p) =>
        {
            if (!await CanManage(db, p, id)) return Results.Forbid();
            var list = await db.Users.Where(x => x.Role == "student" && x.Verified && !db.Enrollments.Any(e => e.CourseId == id && e.StudentId == x.Id)).ToListAsync();
            return Results.Ok(list.Select(x => new { x.Id, x.Username, x.Name }));
        }).RequireAuthorization("staff");
        courses.MapPost("/{id:guid}/students", async (Guid id, EnrollmentInput i, AppDb db, ClaimsPrincipal p) =>
        {
            if (!await CanManage(db, p, id)) return Results.Forbid();
            if (!await db.Courses.AnyAsync(x => x.Id == id)) return Error("Không tìm thấy lớp.", 404);
            if (!await db.Users.AnyAsync(x => x.Id == i.StudentId && x.Role == "student" && x.Verified)) return Error("Sinh viên chưa xác thực hoặc không tồn tại.");
            if (await db.Enrollments.AnyAsync(x => x.CourseId == id && x.StudentId == i.StudentId)) return Error("Sinh viên đã ở trong lớp.", 409);
            db.Enrollments.Add(new Enrollment { CourseId = id, StudentId = i.StudentId }); Security.Audit(db, p, "enrollment.create", $"{id}/{i.StudentId}");
            await db.SaveChangesAsync(); return Results.NoContent();
        }).RequireAuthorization("staff");
        courses.MapDelete("/{id:guid}/students/{studentId:guid}", async (Guid id, Guid studentId, AppDb db, ClaimsPrincipal p) =>
        {
            if (!await CanManage(db, p, id)) return Results.Forbid();
            var e = await db.Enrollments.FindAsync(id, studentId); if (e is null) return Error("Sinh viên không ở trong lớp.", 404);
            db.Enrollments.Remove(e); Security.Audit(db, p, "enrollment.delete", $"{id}/{studentId}"); await db.SaveChangesAsync(); return Results.NoContent();
        }).RequireAuthorization("staff");
    }
    private static bool ValidUser(UserInput i) => Security.ValidUsername(i.Username?.Trim()) && Security.ValidEmail(i.Email?.Trim())
        && !string.IsNullOrWhiteSpace(i.Name) && i.Name.Length <= 100 && i.Role is "admin" or "teacher" or "student";
    private static async Task<bool> ValidCourse(AppDb db, CourseInput i) => !string.IsNullOrWhiteSpace(i.Code) && i.Code.Length <= 30
        && !string.IsNullOrWhiteSpace(i.Name) && i.Name.Length <= 150 && i.Room is { Length: <= 100 }
        && (string.IsNullOrEmpty(i.NfcTagId) || (i.NfcTagId.Length is >= 8 and <= 64 && i.NfcTagId.All(Uri.IsHexDigit)))
        && await db.Users.AnyAsync(x => x.Id == i.TeacherId && x.Role == "teacher" && x.Verified);
    private static void ApplyCourse(Course c, CourseInput i)
    { c.Code = i.Code.Trim().ToUpperInvariant(); c.Name = i.Name.Trim(); c.Room = i.Room.Trim(); c.TeacherId = i.TeacherId; c.NfcTagId = i.NfcTagId?.Trim().ToUpperInvariant(); }
}
