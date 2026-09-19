import 'package:flutter/material.dart';

class RoomPlaybackPage extends StatefulWidget {
  final String roomName;

  const RoomPlaybackPage({super.key, required this.roomName});

  @override
  State<RoomPlaybackPage> createState() => _RoomPlaybackPageState();
}

class _RoomPlaybackPageState extends State<RoomPlaybackPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Header Background
      body: SafeArea(
        child: Column(
          children: [
             // Header
            Container(
              height: 90,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(60),
                ),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      widget.roomName, 
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios_new, size: 24, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            
            // Body with Curved Top Left
             Expanded(
               child: Container(
                 width: double.infinity,
                 decoration: const BoxDecoration(
                   color: Color(0xFFF0F0F0), 
                   borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                 ),
                 child: Column(
                   children: [
                      const SizedBox(height: 30),

                      // Video Player Area (Squircle)
                     Container(
                       margin: const EdgeInsets.symmetric(horizontal: 24),
                       child: AspectRatio(
                         aspectRatio: 1, // Square
                         child: Container(
                           decoration: BoxDecoration(
                             color: const Color(0xFFEAEAEA), 
                             borderRadius: BorderRadius.circular(50), 
                             border: Border.all(color: Colors.black, width: 5), // Thick border
                           ),
                           child: Stack(
                             children: [
                                // Main Icon Content
                               Center(
                                  child: Image.asset(
                                    'assets/images/talking.png', 
                                    width: 180,
                                    height: 180,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.person, size: 90, color: Colors.black),
                                          Icon(Icons.chat_bubble, size: 50, color: Colors.black),
                                          Icon(Icons.person, size: 90, color: Colors.black),
                                        ],
                                      );
                                    },
                                  ),
                               ),
                               // Bottom Controls Overlay
                               Positioned(
                                 bottom: 24,
                                 left: 24,
                                 right: 24,
                                 child: Row(
                                   children: [
                                     const Icon(Icons.play_arrow,
                                         color: Colors.black, size: 36),
                                     const SizedBox(width: 12),
                                     Expanded(
                                       child: Container(
                                         height: 4,
                                         decoration: BoxDecoration(
                                           color: Colors.grey[400],
                                           borderRadius: BorderRadius.circular(2),
                                         ),
                                         child: Row(
                                           children: [
                                             Container(
                                               width: 60, 
                                               height: 4,
                                               decoration: BoxDecoration(
                                                 color: Colors.black,
                                                 borderRadius: BorderRadius.circular(2),
                                               ),
                                             ),
                                             Container(
                                               width: 12,
                                               height: 12,
                                               decoration: const BoxDecoration(
                                                 color: Colors.black,
                                                 shape: BoxShape.circle,
                                               ),
                                             ),
                                           ],
                                         ),
                                       ),
                                     ),
                                     const SizedBox(width: 12),
                                     const Icon(Icons.fullscreen, 
                                         color: Colors.black, size: 30),
                                   ],
                                 ),
                               ),
                             ],
                           ),
                         ),
                       ),
                     ),
                     
                     
                     // Controls Section
                     Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           const SizedBox(height: 30),
                           
                           // Control Buttons Row
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Live Feed Button
                                  GestureDetector(
                                    onTap: () {
                                      // Go to Room Page (Pop current page)
                                      Navigator.pop(context);
                                    },
                                    child: Container(
                                       padding: const EdgeInsets.symmetric(
                                           horizontal: 16, vertical: 10),
                                       decoration: BoxDecoration(
                                         color: Colors.white,
                                         borderRadius: BorderRadius.circular(25),
                                         boxShadow: [
                                            BoxShadow(
                                             color: Colors.black.withOpacity(0.05),
                                             blurRadius: 5,
                                             offset: const Offset(0, 2),
                                           ),
                                         ]
                                       ),
                                       child: Row(
                                         mainAxisSize: MainAxisSize.min,
                                         children: const [
                                           Icon(Icons.play_arrow, color: Colors.black, size: 20),
                                           SizedBox(width: 8),
                                           Text(
                                             'Live Feed',
                                             style: TextStyle(
                                               fontWeight: FontWeight.bold,
                                               color: Colors.black,
                                               fontSize: 14,
                                               fontFamily: 'Comfortaa',
                                             ),
                                           ),
                                         ],
                                       ),
                                     ),
                                  ),
                                  
                                  // Icons Row
                                  Row(
                                    children: [
                                      const Icon(Icons.camera_alt_outlined, size: 26, color: Colors.black),
                                      const SizedBox(width: 16),
                                      const Icon(Icons.radio_button_checked, size: 26, color: Colors.black),
                                      const SizedBox(width: 16),
                                      const Icon(Icons.grid_view_outlined, size: 26, color: Colors.black),
                                      const SizedBox(width: 16),
                                      const Icon(Icons.file_download_outlined, size: 26, color: Colors.black),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                           
                           const SizedBox(height: 20),
                           const Padding(
                             padding: EdgeInsets.symmetric(horizontal: 24),
                             child: Divider(color: Colors.grey, thickness: 0.5),
                           ),
                           
                           // Events List
                             Padding(
                               padding: const EdgeInsets.only(left: 24, top: 16, bottom: 16),
                               child: Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                 decoration: BoxDecoration(
                                   color: Colors.white,
                                   borderRadius: BorderRadius.circular(25),
                                    boxShadow: [
                                        BoxShadow(
                                         color: Colors.black.withOpacity(0.05),
                                         blurRadius: 5,
                                         offset: const Offset(0, 2),
                                       ),
                                     ]
                                 ),
                                   child: const Text('Events', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Comfortaa', color: Colors.black)),
                               ),
                             ),
                             Expanded(
                               child: ListView(
                                 padding: const EdgeInsets.symmetric(horizontal: 24),
                                 children: [
                                   _buildEventCard('10:00 AM', 'Person fell in the Kitchen', '6 hour ago'),
                                   const SizedBox(height: 12),
                                   _buildEventCard('09:58 PM', 'Main door left open', '4 hour ago'),
                                    const SizedBox(height: 12),
                                   // Added "No events yet" to fill space or logic if needed, but mockup shows list.
                                 ],
                               ),
                             )
                         ],
                       ),
                     ),
                   ],
                 ),
               ),
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(String time, String description, String ago) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
           BoxShadow(
             color: Colors.black.withOpacity(0.03),
             blurRadius: 5,
             offset: const Offset(0, 2),
           ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontFamily: 'Comfortaa',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13, 
                    color: Colors.grey[400],
                     fontFamily: 'Comfortaa',
                  ),
                ),
              ],
            ),
          ),
          Text(
            ago,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              fontFamily: 'Comfortaa',
            ),
          ),
        ],
      ),
    );
  }
}
