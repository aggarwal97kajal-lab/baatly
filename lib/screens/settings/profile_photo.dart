import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Take / choose / remove the profile photo (square crop, uploaded small).
Future<void> changeProfilePhoto(BuildContext context) async {
  final s = AppState.instance;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('Profile photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        ),
        ListTile(
          leading: Icon(Icons.photo_camera_outlined, color: ctx.primary),
          title: const Text('Camera'),
          onTap: () => Navigator.pop(ctx, 'camera'),
        ),
        ListTile(
          leading: Icon(Icons.photo_library_outlined, color: ctx.primary),
          title: const Text('Gallery'),
          onTap: () => Navigator.pop(ctx, 'gallery'),
        ),
        if (s.myPhoto != null)
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB3261E)),
            title: const Text('Remove photo', style: TextStyle(color: Color(0xFFB3261E))),
            onTap: () => Navigator.pop(ctx, 'remove'),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  final online = kHasBackend && Api.instance.loggedIn;
  void toast(String t) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  if (choice == 'remove') {
    try {
      if (online) await Messenger.instance.removeMyPhoto();
      s.toggle(() => s.myPhoto = null);
      toast('Profile photo removed');
    } on ApiException catch (e) {
      toast(e.message);
    }
    return;
  }

  XFile? file;
  try {
    file = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600);
  } catch (_) {
    toast('Camera / photos permission needed');
    return;
  }
  if (file == null) return;
  CroppedFile? cropped;
  try {
    cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      maxWidth: 640,
      maxHeight: 640,
      compressQuality: 78,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Move and scale',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          statusBarLight: false,
          backgroundColor: Colors.black,
          activeControlsWidgetColor: Mitti.terracotta,
          lockAspectRatio: true,
          hideBottomControls: true,
          cropStyle: CropStyle.circle,
        ),
      ],
    );
  } catch (e) {
    toast("Couldn't open the cropper ($e)");
    return;
  }
  if (cropped == null) return;
  // Keep our own copy (the cropper's file lives in cache).
  final dir = await getApplicationDocumentsDirectory();
  final dest = File('${dir.path}/my_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await File(cropped.path).copy(dest.path);
  try {
    if (online) await Messenger.instance.uploadMyPhoto(dest.path);
    final old = s.myPhoto;
    s.toggle(() => s.myPhoto = dest.path);
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    toast('Profile photo updated');
  } on ApiException catch (e) {
    toast(e.message);
  } catch (_) {
    toast("Couldn't upload. Check your internet.");
  }
}
