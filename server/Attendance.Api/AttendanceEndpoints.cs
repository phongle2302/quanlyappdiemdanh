using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using static Attendance.Api.AuthEndpoints;
using static Attendance.Api.ManagementEndpoints;
namespace Attendance.Api;

public static class AttendanceEndpoints
{
    public static void MapAttendance(this WebApplication app)
    {
        var lessons = app.MapGroup("/api/lessons").RequireAuthorization();
        lessons.MapGet("/", async (AppDb db, ClaimsPrincipal p) =>
        {
            var visible = VisibleCourses(db, p).Select(c => c.Id);
            return Results.Ok((await db.Lessons.Where(x => visible.Contains(x.CourseId)).ToListAsync()).OrderByDescending(x => x.StartsAt).Select(PublicLesson));
        });
        lessons.MapPost("/", async (LessonInput i, AppDb db, ClaimsPrincipal p) =>
        {
            if (!await db.Courses.AnyAsync(x => x.Id == i.CourseId)) return Error("Không tìm thấy lớp.", 404);
            if (!await CanManage(db, p, i.CourseId)) return Results.Forbid();
            if (!ValidLesson(i)) return Error("Kiểm tra thời gian, tọa độ và bán kính (10–500 mét, tối đa 12 giờ).");
            var l = new Lesson(); ApplyLesson(l, i); db.Lessons.Add(l); Security.Audit(db, p, "lesson.create", l.Id);
            await db.SaveChangesAsync(); return Results.Created($"/api/lessons/{l.Id}", PublicLesson(l));
        }).RequireAuthorization("staff");
        lessons.MapPut("/{id:guid}", async (Guid id, LessonInput i, AppDb db, ClaimsPrincipal p) =>
        {
            var l = await db.Lessons.FindAsync(id); if (l is null) return Error("Không tìm thấy buổi học.", 404);
            if (!await CanManage(db, p, l.CourseId)) return Results.Forbid();
            if (i.CourseId != l.CourseId || !ValidLesson(i)) return Error("Thông tin buổi học không hợp lệ; không thể chuyển lớp.");
            ApplyLesson(l, i); l.QrCode = ""; Security.Audit(db, p, "lesson.update", id);
            await db.SaveChangesAsync(); return Results.Ok(PublicLesson(l));
        }).RequireAuthorization("staff");
        lessons.MapDelete("/{id:guid}", async (Guid id, AppDb db, ClaimsPrincipal p) =>
        {
            var l = await db.Lessons.FindAsync(id); if (l is null) return Error("Không tìm thấy buổi học.", 404);
            if (!await CanManage(db, p, l.CourseId)) return Results.Forbid();
            db.Lessons.Remove(l); Security.Audit(db, p, "lesson.delete", id); await db.SaveChangesAsync(); return Results.NoContent();
        }).RequireAuthorization("staff");
        lessons.MapPost("/{id:guid}/qr", async (Guid id, AppDb db, ClaimsPrincipal p) =>
        {
            var l = await db.Lessons.FindAsync(id); if (l is null) return Error("Không tìm thấy buổi học.", 404);
            if (!await CanManage(db, p, l.CourseId)) return Results.Forbid();
            var now = DateTimeOffset.UtcNow;
            if (l.Closed || now < l.StartsAt || now >= l.EndsAt) return Error("Buổi học chưa mở hoặc đã kết thúc.");
            l.QrCode = Security.Token(); l.QrExpiresAt = now.AddSeconds(60) < l.EndsAt ? now.AddSeconds(60) : l.EndsAt;
            await db.SaveChangesAsync(); return Results.Ok(new { lessonId = id, code = l.QrCode, expiresAt = l.QrExpiresAt });
        }).RequireAuthorization("staff");
        var attendance = app.MapGroup("/api/attendance").RequireAuthorization();
        attendance.MapGet("/", async (AppDb db, ClaimsPrincipal p, Guid? lessonId) =>
        {
            var q = db.AttendanceRecords.AsQueryable();
            if (p.IsInRole("student")) q = q.Where(x => x.StudentId == p.UserId());
            else if (!p.Admin()) q = q.Where(x => db.Lessons.Any(l => l.Id == x.LessonId && db.Courses.Any(c => c.Id == l.CourseId && c.TeacherId == p.UserId())));
            if (lessonId.HasValue) q = q.Where(x => x.LessonId == lessonId);
            return Results.Ok((await q.ToListAsync()).OrderByDescending(x => x.CheckedAt));
        });
        attendance.MapPost("/check-in", async (CheckInInput i, AppDb db, ClaimsPrincipal p) =>
        {
            var l = await db.Lessons.FindAsync(i.LessonId); if (l is null) return Error("Không tìm thấy buổi học.", 404);
            var now = DateTimeOffset.UtcNow;
            if (l.Closed || now < l.StartsAt || now >= l.EndsAt) return Error("Ngoài thời gian điểm danh.");
            if (!await db.Enrollments.AnyAsync(e => e.CourseId == l.CourseId && e.StudentId == p.UserId())) return Results.Forbid();
            if (!Security.ValidCoordinates(i.Latitude, i.Longitude) || !double.IsFinite(i.AccuracyMeters) || i.AccuracyMeters is <= 0 or > 50
                || (now - i.PositionTime).TotalSeconds is > 60 or < -10) return Error("Vị trí chưa đủ chính xác hoặc đã cũ. Hãy bật GPS và thử lại.");
            var distance = Security.Distance(l.Latitude, l.Longitude, i.Latitude, i.Longitude);
            if (distance > l.RadiusMeters) return Error($"Bạn cách lớp {Math.Round(distance)} m, ngoài bán kính {l.RadiusMeters} m.");
            if (i.Method == "qr")
            {
                if (string.IsNullOrEmpty(i.Code) || l.QrCode != i.Code || l.QrExpiresAt <= now) return Error("QR không hợp lệ hoặc hết hạn.");
            }
            else if (i.Method == "nfc")
            {
                var c = (await db.Courses.FindAsync(l.CourseId))!;
                if (string.IsNullOrEmpty(c.NfcTagId) || c.NfcTagId != i.NfcTagId?.ToUpperInvariant()) return Error("Thẻ NFC không thuộc lớp này.");
            }
            else if (i.Method != "biometric") return Error("Phương thức điểm danh không hợp lệ.");
            if (await db.AttendanceRecords.AnyAsync(x => x.LessonId == l.Id && x.StudentId == p.UserId())) return Error("Bạn đã điểm danh buổi này.", 409);
            var r = new AttendanceRecord { LessonId = l.Id, StudentId = p.UserId(), Method = i.Method, Latitude = i.Latitude, Longitude = i.Longitude,
                AccuracyMeters = i.AccuracyMeters, DistanceMeters = distance, Status = now > l.StartsAt.AddMinutes(15) ? "late" : "present" };
            db.AttendanceRecords.Add(r); Security.Audit(db, p, "attendance.check-in", r.Id); await db.SaveChangesAsync();
            return Results.Created($"/api/attendance/{r.Id}", r);
        }).RequireAuthorization("student");
        attendance.MapPost("/", async (AttendanceInput i, AppDb db, ClaimsPrincipal p) =>
        {
            var l = await db.Lessons.FindAsync(i.LessonId); if (l is null) return Error("Không tìm thấy buổi học.", 404);
            if (!await CanManage(db, p, l.CourseId)) return Results.Forbid();
            if (!ValidAttendance(i) || !await db.Enrollments.AnyAsync(x => x.CourseId == l.CourseId && x.StudentId == i.StudentId)) return Error("Sinh viên hoặc trạng thái không hợp lệ.");
            if (await db.AttendanceRecords.AnyAsync(x => x.LessonId == i.LessonId && x.StudentId == i.StudentId)) return Error("Đã có bản ghi điểm danh.", 409);
            var r = new AttendanceRecord { LessonId = i.LessonId, StudentId = i.StudentId, Method = "manual", Status = i.Status, Note = i.Note };
            db.AttendanceRecords.Add(r); Security.Audit(db, p, "attendance.create", r.Id); await db.SaveChangesAsync(); return Results.Created($"/api/attendance/{r.Id}", r);
        }).RequireAuthorization("staff");
        attendance.MapPut("/{id:guid}", async (Guid id, AttendanceInput i, AppDb db, ClaimsPrincipal p) =>
        {
            var r = await db.AttendanceRecords.FindAsync(id); if (r is null) return Error("Không tìm thấy điểm danh.", 404);
            var l = (await db.Lessons.FindAsync(r.LessonId))!;
            if (!await CanManage(db, p, l.CourseId)) return Results.Forbid();
            if (i.StudentId != r.StudentId || i.LessonId != r.LessonId || !ValidAttendance(i)) return Error("Chỉ được sửa trạng thái và ghi chú.");
            r.Status = i.Status; r.Note = i.Note; Security.Audit(db, p, "attendance.update", id);
            await db.SaveChangesAsync(); return Results.Ok(r);
        }).RequireAuthorization("staff");
        attendance.MapDelete("/{id:guid}", async (Guid id, AppDb db, ClaimsPrincipal p) =>
        {
            var r = await db.AttendanceRecords.FindAsync(id); if (r is null) return Error("Không tìm thấy điểm danh.", 404);
            var l = (await db.Lessons.FindAsync(r.LessonId))!; if (!await CanManage(db, p, l.CourseId)) return Results.Forbid();
            db.AttendanceRecords.Remove(r); Security.Audit(db, p, "attendance.delete", id); await db.SaveChangesAsync(); return Results.NoContent();
        }).RequireAuthorization("staff");
    }
    private static object PublicLesson(Lesson l) => new { l.Id, l.CourseId, l.Title, l.StartsAt, l.EndsAt, l.Latitude, l.Longitude, l.RadiusMeters, l.Closed };
    private static bool ValidLesson(LessonInput i) => !string.IsNullOrWhiteSpace(i.Title) && i.Title.Length <= 150 && i.EndsAt > i.StartsAt
        && (i.EndsAt - i.StartsAt).TotalHours <= 12 && Security.ValidCoordinates(i.Latitude, i.Longitude) && double.IsFinite(i.RadiusMeters) && i.RadiusMeters is >= 10 and <= 500;
    private static void ApplyLesson(Lesson l, LessonInput i)
    { l.CourseId = i.CourseId; l.Title = i.Title.Trim(); l.StartsAt = i.StartsAt; l.EndsAt = i.EndsAt; l.Latitude = i.Latitude; l.Longitude = i.Longitude; l.RadiusMeters = i.RadiusMeters; l.Closed = i.Closed; }
    private static bool ValidAttendance(AttendanceInput i) => i.Status is "present" or "late" or "absent" or "excused" && i.Note is { Length: <= 500 };
}
