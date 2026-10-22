import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'ui.dart';

class AuthPage extends StatefulWidget {
  final Api api;
  const AuthPage({required this.api, super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  var form = GlobalKey<FormState>();
  final scroll = ScrollController();
  final username = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController(),
      name = TextEditingController(),
      email = TextEditingController(),
      otp = TextEditingController();
  bool register = false, busy = false, visible = false;
  String? challenge, error;
  String deliveryMode = 'smtp';
  String? deliveryMessage;

  @override
  void dispose() {
    for (final c in [username, password, confirmation, name, email, otp]) {
      c.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  void changeMode(bool value) {
    FocusScope.of(context).unfocus();
    setState(() {
      register = value;
      challenge = null;
      deliveryMessage = null;
      deliveryMode = 'smtp';
      error = null;
      visible = false;
      otp.clear();
      confirmation.clear();
      form = GlobalKey<FormState>();
    });
    resetScroll();
  }

  void resetScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (challenge != null) {
        await widget.api.verify(challenge!, otp.text);
      } else {
        final data = await widget.api.request(
          'POST',
          register ? '/auth/register' : '/auth/login',
          {
            'username': username.text.trim(),
            'password': password.text,
            if (register) ...{
              'name': name.text.trim(),
              'email': email.text.trim(),
            },
          },
        ) as Json;
        if (data['token'] is String) {
          await widget.api.acceptSession(data);
        } else if (mounted) {
          setState(() {
            challenge = data['challengeId'] as String;
            deliveryMode = data['deliveryMode'] as String? ?? 'smtp';
            deliveryMessage = data['message'] as String?;
            form = GlobalKey<FormState>();
          });
          resetScroll();
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration decoration(String label, String hint, IconData icon) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 21, color: const Color(0xff67808e)),
        filled: true,
        fillColor: const Color(0xfff6f8fa),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        errorMaxLines: 3,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xffe3eaf0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xffe3eaf0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: teal, width: 1.5),
        ),
      );

  Widget field(
    TextEditingController c,
    String label,
    String hint,
    IconData icon, {
    TextInputType? keyboard,
    Iterable<String>? autofill,
    TextCapitalization capitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(label),
      controller: c,
      enabled: !busy,
      keyboardType: keyboard,
      autofillHints: autofill,
      textCapitalization: capitalization,
      textInputAction: TextInputAction.next,
      autocorrect: capitalization == TextCapitalization.words,
      decoration: decoration(label, hint, icon),
      validator:
          validator ??
          (v) => v == null || v.trim().isEmpty
              ? 'Vui lòng nhập ${label.toLowerCase()}'
              : null,
    ),
  );

  Widget modeButton(bool value, String label) {
    final selected = register == value;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          key: ValueKey(value ? 'register-tab' : 'login-tab'),
          onPressed: busy ? null : () => changeMode(value),
          style: TextButton.styleFrom(
            foregroundColor: selected ? navy : const Color(0xff667987),
            backgroundColor: selected ? Colors.white : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget notice(IconData icon, String text, {bool warning = false}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: warning ? const Color(0xfffff4e4) : const Color(0xffedf7f6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 19,
              color: warning ? const Color(0xff9b5b10) : teal,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: warning
                      ? const Color(0xff89581c)
                      : const Color(0xff46656e),
                ),
              ),
            ),
          ],
        ),
      );

  Widget passwordField({bool repeat = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(repeat ? 'confirm-password' : 'password'),
      controller: repeat ? confirmation : password,
      enabled: !busy,
      obscureText: !visible,
      autofillHints: repeat
          ? null
          : [register ? AutofillHints.newPassword : AutofillHints.password],
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: register && !repeat
          ? TextInputAction.next
          : TextInputAction.done,
      decoration:
          decoration(
            repeat ? 'Xác nhận mật khẩu' : 'Mật khẩu',
            repeat ? 'Nhập lại mật khẩu' : 'Nhập mật khẩu của bạn',
            Icons.lock_outline_rounded,
          ).copyWith(
            suffixIcon: repeat
                ? null
                : IconButton(
                    tooltip: visible ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                    onPressed: busy
                        ? null
                        : () => setState(() => visible = !visible),
                    icon: Icon(
                      visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 21,
                    ),
                  ),
          ),
      validator: (v) {
        if (v == null || v.isEmpty) {
          return repeat
              ? 'Vui lòng nhập lại mật khẩu'
              : 'Vui lòng nhập mật khẩu';
        }
        if (repeat) {
          return v == password.text ? null : 'Mật khẩu xác nhận chưa khớp';
        }
        if (register &&
            (v.length < 10 ||
                v.length > 128 ||
                v == v.toLowerCase() ||
                v == v.toUpperCase() ||
                !RegExp(r'[0-9]').hasMatch(v))) {
          return 'Dùng 10–128 ký tự, gồm chữ hoa, chữ thường và số';
        }
        return null;
      },
      onFieldSubmitted: register && !repeat ? null : (_) => submit(),
    ),
  );

  Widget get formContents => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (challenge == null) ...[
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xfff0f4f6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              modeButton(false, 'Đăng nhập'),
              const SizedBox(width: 4),
              modeButton(true, 'Đăng ký'),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ] else ...[
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xffe7f4f2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: teal,
              size: 30,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
      Text(
        challenge != null
            ? deliveryMode == 'pickup'
                  ? 'OTP của bản thử nghiệm'
                  : 'Kiểm tra hộp thư'
            : register
            ? 'Tạo tài khoản sinh viên'
            : 'Chào mừng trở lại',
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: navy,
          height: 1.25,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        challenge != null
            ? register
                  ? 'Chỉ còn một bước để xác thực email của bạn.'
                  : 'Xác thực để tiếp tục vào lớp học của bạn.'
            : register
            ? 'Tham gia lớp học và theo dõi điểm danh của bạn.'
            : 'Đăng nhập để bắt đầu buổi học hôm nay.',
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xff6a7c89),
          height: 1.55,
        ),
      ),
      const SizedBox(height: 24),
      if (challenge != null) ...[
        notice(
          deliveryMode == 'pickup'
              ? Icons.info_outline_rounded
              : Icons.mail_outline_rounded,
          deliveryMessage ?? 'Nhập mã OTP gồm 6 số gửi đến email đã đăng ký. Mã có hiệu lực 5 phút.',
          warning: deliveryMode == 'pickup',
        ),
        if (register && deliveryMode != 'pickup')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              email.text.trim(),
              style: const TextStyle(color: teal, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 20),
        TextFormField(
          key: const ValueKey('otp'),
          controller: otp,
          enabled: !busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            letterSpacing: 8,
            fontWeight: FontWeight.w700,
            color: navy,
          ),
          decoration: decoration(
            'Mã OTP',
            '000000',
            Icons.password_rounded,
          ).copyWith(counterText: ''),
          validator: (v) => v?.length == 6 ? null : 'Nhập đủ 6 chữ số',
          onFieldSubmitted: (_) => submit(),
        ),
        const SizedBox(height: 8),
        const Text(
          'Mã có hiệu lực trong 5 phút.',
          style: TextStyle(fontSize: 12, color: Color(0xff6a7c89)),
        ),
      ] else ...[
        if (register) ...[
          field(
            name,
            'Họ và tên',
            'Nguyễn Văn An',
            Icons.badge_outlined,
            autofill: const [AutofillHints.name],
            capitalization: TextCapitalization.words,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Vui lòng nhập họ và tên'
                : v.trim().length > 100
                ? 'Họ tên tối đa 100 ký tự'
                : null,
          ),
          field(
            email,
            'Email',
            'ban@example.com',
            Icons.alternate_email_rounded,
            keyboard: TextInputType.emailAddress,
            autofill: const [AutofillHints.email],
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Vui lòng nhập email'
                : v.trim().length > 254 ||
                      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
                ? 'Địa chỉ email chưa hợp lệ'
                : null,
          ),
        ],
        field(
          username,
          'Tên đăng nhập',
          'Nhập tên đăng nhập',
          Icons.person_outline_rounded,
          autofill: const [AutofillHints.username],
          validator: (v) => v == null || v.trim().isEmpty
              ? 'Vui lòng nhập tên đăng nhập'
              : register &&
                    !RegExp(r'^[a-zA-Z0-9_.-]{3,40}$').hasMatch(v.trim())
              ? 'Dùng 3–40 ký tự: chữ, số, dấu chấm, gạch dưới hoặc gạch ngang'
              : null,
        ),
        passwordField(),
        if (register) ...[
          passwordField(repeat: true),
          const Text(
            'Mật khẩu gồm 10–128 ký tự, có chữ hoa, chữ thường và số.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xff6a7c89),
            ),
          ),
        ],
      ],
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Semantics(
            liveRegion: true,
            child: notice(Icons.error_outline_rounded, error!, warning: true),
          ),
        ),
      const SizedBox(height: 24),
      SizedBox(
        height: 54,
        child: FilledButton(
          onPressed: busy ? null : submit,
          style: FilledButton.styleFrom(
            backgroundColor: teal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        challenge != null
                            ? 'Xác thực và tiếp tục'
                            : register
                            ? 'Tạo tài khoản'
                            : 'Đăng nhập',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded, size: 19),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: busy
            ? null
            : () => changeMode(challenge != null ? register : !register),
        child: Text(
          challenge != null
              ? 'Quay lại để gửi mã mới'
              : register
              ? 'Đã có tài khoản? Đăng nhập'
              : 'Chưa có tài khoản? Đăng ký',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      if (challenge == null) ...[
        const SizedBox(height: 12),
        notice(
          register
              ? Icons.mark_email_read_outlined
              : Icons.verified_user_outlined,
          register ? 'Mã xác thực sẽ được gửi đến email bạn đăng ký.' : 'Giáo viên đăng nhập bằng mật khẩu. Sinh viên và quản trị viên xác thực thêm OTP qua email.',
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff0f5f7),
    body: Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 310,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(36),
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff102f46), Color(0xff155263)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(right: -55, top: -80, child: _orb(230)),
                  Positioned(right: 60, bottom: -105, child: _orb(200)),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              controller: scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xff2a737e),
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .16),
                              ),
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              color: Colors.white,
                              size: 29,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Attendly',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 27,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.8,
                                  ),
                                ),
                                Text(
                                  'Kết nối lớp học của bạn',
                                  style: TextStyle(
                                    color: Color(0xffb8d7dd),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.auto_awesome_outlined,
                            color: Color(0xff7bc9c3),
                            size: 23,
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xff102f46)
                                  .withValues(alpha: .08),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: AutofillGroup(
                          child: Form(key: form, child: formContents),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Color(0xff7c929e),
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Đúng lớp học. Trọn vẹn buổi học.',
                              style: TextStyle(
                                color: Color(0xff7c929e),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _orb(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: .025),
      border: Border.all(color: Colors.white.withValues(alpha: .07), width: 1),
    ),
  );
}
