import 'package:flutter/material.dart';

class UpdatePopup extends StatelessWidget {
  const UpdatePopup({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 170,
        width: 280,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10)
        ),
        child: Column(
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/launcher_icon/icon.png',
                  width: 25,
                ),
                const SizedBox(width: 5),
                const Text(
                  'Perhatian',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Ada versi baru nih, Yuk update aplikasinya!',
              style: TextStyle(
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 5),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                primary: const Color(0xFFEC3528),
              ),
              child: const Text('Update'),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}