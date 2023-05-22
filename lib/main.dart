import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'dart:async';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Average Speed App With outliers removal',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LocationPage(),
    );
  }
}

class LocationPage extends StatefulWidget {
  @override
  _LocationPageState createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  String _averageSpeed = '';
  List<double> _longitude = [];
  List<double> _latitude = [];

  // Haversine formula
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Radius of the earth in kilometers
    var dLat = _toRadians(lat2 - lat1);
    var dLon = _toRadians(lon2 - lon1);
    var a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));
    var d = R * c; // Distance in kilometers
    return d;
  }

  double _toRadians(double degrees) {
    return degrees * pi / 180;
  }

  Future<void> _requestPermission() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      setState(() {
        _averageSpeed = 'Permission denied';
      });
    } else if (permission == LocationPermission.deniedForever) {
      setState(() {
        _averageSpeed =
            'Permission denied forever, please enable location from settings';
      });
    } else {
      setState(() {
        _averageSpeed = 'Calculating...';
      });
      _getCurrentLocation();
    }
  }

  void _getCurrentLocation() async {
    setState(() {
      _latitude = [];
      _longitude = [];
    });
    int count = 0;
    Timer.periodic(Duration(seconds: 1), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation);

        setState(() {
          _latitude.add(position.latitude);
          _longitude.add(position.longitude);
        });

        setState(() {
          _averageSpeed = 'Waiting for ${30 - count} seconds...';
        });

        count++;
        if (count == 31) {
          _removeOutliers();
          double totalSpeeds = 0.0;
          for (var i = 1; i < _longitude.length; i++) {
            var speed = calculateDistance(
              _latitude[i - 1],
              _longitude[i - 1],
              _latitude[i],
              _longitude[i],
            );
            totalSpeeds += speed;
          }
          setState(() {
            _averageSpeed =
                'Average Speed: ${(totalSpeeds * 1000 / _longitude.length).toStringAsFixed(2)} m/s\n';
          });

          timer.cancel();
        }
      } catch (error) {
        print(error);
      }
    });
  }

  void _removeOutliers() {
    const int k = 3; // Number of clusters
    const int maxIterations = 10;

    List<double> longitudeCopy = List.from(_longitude);
    List<double> latitudeCopy = List.from(_latitude);

    if (longitudeCopy.length <= k) {
      return;
    }

    List<double> longitudeClusters = [];
    List<double> latitudeClusters = [];

    // Initialize cluster centers randomly
    Random random = Random();
    for (var i = 0; i < k; i++) {
      int index = random.nextInt(longitudeCopy.length);
      longitudeClusters.add(longitudeCopy[index]);
      latitudeClusters.add(latitudeCopy[index]);
    }

    // to put the index of the center of each cluster
    List<int> clusterAssignments = List.filled(longitudeCopy.length, 0);

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      bool clustersChanged = false;

      // Assign each point to the nearest cluster
      for (var i = 0; i < longitudeCopy.length; i++) {
        double longitude = longitudeCopy[i];
        double latitude = latitudeCopy[i];

        double minDistance = double.infinity;
        int clusterIndex = -1;

        // department into three clusters and assign each point to the nearest cluster
        for (var j = 0; j < k; j++) {
          double clusterLongitude = longitudeClusters[j];
          double clusterLatitude = latitudeClusters[j];

          // calculate the distance between the point and the cluster center
          double distance = calculateDistance(
            latitude,
            longitude,
            clusterLatitude,
            clusterLongitude,
          );

          // if the distance is less than the minimum distance, then update the minimum distance (that means the point is closer to this cluster)
          if (distance < minDistance) {
            minDistance = distance;
            clusterIndex = j;
          }
        }

        // if the point is not assigned to the cluster, then assign it to the cluster
        if (clusterAssignments[i] != clusterIndex) {
          clusterAssignments[i] = clusterIndex;
          clustersChanged = true;
        }
      }

      // Update cluster centers
      for (var j = 0; j < k; j++) {
        double sumLongitude = 0.0;
        double sumLatitude = 0.0;
        int count = 0;

        for (var i = 0; i < longitudeCopy.length; i++) {
          if (clusterAssignments[i] == j) {
            sumLongitude += longitudeCopy[i];
            sumLatitude += latitudeCopy[i];
            count++;
          }
        }
        // If there are points assigned to the cluster, then update the cluster center
        if (count > 0) {
          double newClusterLongitude = sumLongitude / count;
          double newClusterLatitude = sumLatitude / count;
          // If the cluster center changed, then update it
          if (newClusterLongitude != longitudeClusters[j] ||
              newClusterLatitude != latitudeClusters[j]) {
            longitudeClusters[j] = newClusterLongitude;
            latitudeClusters[j] = newClusterLatitude;
            clustersChanged = true;
          }
        }
      }

      // If no point changed clusters then done
      if (!clustersChanged) {
        break;
      }
    }

    // Remove outliers by keeping points belonging to the largest cluster
    List<double> filteredLongitude = [];
    List<double> filteredLatitude = [];

    int largestClusterSize = 0;
    int largestClusterIndex = -1;

    for (var j = 0; j < k; j++) {
      // to get the largest cluster
      int clusterSize = clusterAssignments.where((index) => index == j).length;
      if (clusterSize > largestClusterSize) {
        largestClusterSize = clusterSize;
        largestClusterIndex = j;
      }
    }
    
    for (var i = 0; i < longitudeCopy.length; i++) {
      if (clusterAssignments[i] == largestClusterIndex) {
        filteredLongitude.add(longitudeCopy[i]);
        filteredLatitude.add(latitudeCopy[i]);
      }
    }

    setState(() {
      _longitude = filteredLongitude;
      _latitude = filteredLatitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Average Speed App With Outlier Removal'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _averageSpeed,
              style: TextStyle(fontSize: 20),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _requestPermission,
              child: Text('Get Average Speed'),
            ),
          ],
        ),
      ),
    );
  }
}
