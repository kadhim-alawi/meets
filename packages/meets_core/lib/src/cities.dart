/// A named city used to label Qloo heatmap cells.
class City {
  const City(this.name, this.country, this.lat, this.lon);

  final String name;

  /// ISO country code, matching [Market.code].
  final String country;
  final double lat;
  final double lon;
}

/// Cities per market, with approximate centre coordinates. Heatmap cells are
/// assigned to the nearest one within a radius, so the list only needs to be
/// good enough to name where an audience clusters.
const List<City> kCities = [
  // United States
  City('New York', 'US', 40.7128, -74.0060), City('Los Angeles', 'US', 34.0522, -118.2437),
  City('Chicago', 'US', 41.8781, -87.6298), City('Houston', 'US', 29.7604, -95.3698),
  City('Phoenix', 'US', 33.4484, -112.0740), City('Philadelphia', 'US', 39.9526, -75.1652),
  City('San Antonio', 'US', 29.4241, -98.4936), City('San Diego', 'US', 32.7157, -117.1611),
  City('Dallas', 'US', 32.7767, -96.7970), City('Austin', 'US', 30.2672, -97.7431),
  City('San Jose', 'US', 37.3382, -121.8863), City('San Francisco', 'US', 37.7749, -122.4194),
  City('Seattle', 'US', 47.6062, -122.3321), City('Portland', 'US', 45.5152, -122.6784),
  City('Denver', 'US', 39.7392, -104.9903), City('Boston', 'US', 42.3601, -71.0589),
  City('Washington, DC', 'US', 38.9072, -77.0369), City('Baltimore', 'US', 39.2904, -76.6122),
  City('Atlanta', 'US', 33.7490, -84.3880), City('Miami', 'US', 25.7617, -80.1918),
  City('Orlando', 'US', 28.5383, -81.3792), City('Tampa', 'US', 27.9506, -82.4572),
  City('Nashville', 'US', 36.1627, -86.7816), City('Memphis', 'US', 35.1495, -90.0490),
  City('New Orleans', 'US', 29.9511, -90.0715), City('Charlotte', 'US', 35.2271, -80.8431),
  City('Raleigh', 'US', 35.7796, -78.6382), City('Richmond', 'US', 37.5407, -77.4360),
  City('Pittsburgh', 'US', 40.4406, -79.9959), City('Cleveland', 'US', 41.4993, -81.6944),
  City('Columbus', 'US', 39.9612, -82.9988), City('Cincinnati', 'US', 39.1031, -84.5120),
  City('Detroit', 'US', 42.3314, -83.0458), City('Indianapolis', 'US', 39.7684, -86.1581),
  City('Milwaukee', 'US', 43.0389, -87.9065), City('Minneapolis', 'US', 44.9778, -93.2650),
  City('St. Louis', 'US', 38.6270, -90.1994), City('Kansas City', 'US', 39.0997, -94.5786),
  City('Omaha', 'US', 41.2565, -95.9345), City('Oklahoma City', 'US', 35.4676, -97.5164),
  City('Salt Lake City', 'US', 40.7608, -111.8910), City('Las Vegas', 'US', 36.1699, -115.1398),
  City('Albuquerque', 'US', 35.0844, -106.6504), City('Tucson', 'US', 32.2226, -110.9747),
  City('Sacramento', 'US', 38.5816, -121.4944), City('Boise', 'US', 43.6150, -116.2023),
  City('Madison', 'US', 43.0731, -89.4012), City('Louisville', 'US', 38.2527, -85.7585),
  City('Buffalo', 'US', 42.8864, -78.8784), City('Burlington', 'US', 44.4759, -73.2121),
  City('Providence', 'US', 41.8240, -71.4128), City('Hartford', 'US', 41.7658, -72.6734),
  City('Asheville', 'US', 35.5951, -82.5515), City('Savannah', 'US', 32.0809, -81.0912),
  City('Birmingham, AL', 'US', 33.5186, -86.8104), City('Jacksonville', 'US', 30.3322, -81.6557),
  City('Honolulu', 'US', 21.3069, -157.8583), City('Anchorage', 'US', 61.2181, -149.9003),
  City('Spokane', 'US', 47.6588, -117.4260), City('Des Moines', 'US', 41.5868, -93.6250),
  City('Ann Arbor', 'US', 42.2808, -83.7430), City('Santa Fe', 'US', 35.6870, -105.9378),
  City('Missoula', 'US', 46.8721, -113.9940), City('Eugene', 'US', 44.0521, -123.0868),
  City('Fresno', 'US', 36.7378, -119.7871), City('El Paso', 'US', 31.7619, -106.4850),
  // United Kingdom
  City('London', 'GB', 51.5074, -0.1278), City('Manchester', 'GB', 53.4808, -2.2426),
  City('Birmingham', 'GB', 52.4862, -1.8904), City('Leeds', 'GB', 53.8008, -1.5491),
  City('Glasgow', 'GB', 55.8642, -4.2518), City('Edinburgh', 'GB', 55.9533, -3.1883),
  City('Liverpool', 'GB', 53.4084, -2.9916), City('Bristol', 'GB', 51.4545, -2.5879),
  City('Sheffield', 'GB', 53.3811, -1.4701), City('Newcastle', 'GB', 54.9783, -1.6178),
  City('Nottingham', 'GB', 52.9548, -1.1581), City('Cardiff', 'GB', 51.4816, -3.1791),
  City('Belfast', 'GB', 54.5973, -5.9301), City('Brighton', 'GB', 50.8225, -0.1372),
  City('Oxford', 'GB', 51.7520, -1.2577), City('Cambridge', 'GB', 52.2053, 0.1218),
  // Canada
  City('Toronto', 'CA', 43.6532, -79.3832), City('Montreal', 'CA', 45.5019, -73.5674),
  City('Vancouver', 'CA', 49.2827, -123.1207), City('Calgary', 'CA', 51.0447, -114.0719),
  City('Edmonton', 'CA', 53.5461, -113.4938), City('Ottawa', 'CA', 45.4215, -75.6972),
  City('Winnipeg', 'CA', 49.8951, -97.1384), City('Quebec City', 'CA', 46.8139, -71.2080),
  City('Halifax', 'CA', 44.6488, -63.5752), City('Victoria', 'CA', 48.4284, -123.3656),
  City('Saskatoon', 'CA', 52.1579, -106.6702),
  // Australia
  City('Sydney', 'AU', -33.8688, 151.2093), City('Melbourne', 'AU', -37.8136, 144.9631),
  City('Brisbane', 'AU', -27.4698, 153.0251), City('Perth', 'AU', -31.9505, 115.8605),
  City('Adelaide', 'AU', -34.9285, 138.6007), City('Canberra', 'AU', -35.2809, 149.1300),
  City('Gold Coast', 'AU', -28.0167, 153.4000), City('Hobart', 'AU', -42.8821, 147.3272),
  // Ireland
  City('Dublin', 'IE', 53.3498, -6.2603), City('Cork', 'IE', 51.8985, -8.4756),
  City('Galway', 'IE', 53.2707, -9.0568), City('Limerick', 'IE', 52.6638, -8.6267),
  // New Zealand
  City('Auckland', 'NZ', -36.8485, 174.7633), City('Wellington', 'NZ', -41.2865, 174.7762),
  City('Christchurch', 'NZ', -43.5321, 172.6362), City('Dunedin', 'NZ', -45.8788, 170.5028),
  // Germany
  City('Berlin', 'DE', 52.5200, 13.4050), City('Hamburg', 'DE', 53.5511, 9.9937),
  City('Munich', 'DE', 48.1351, 11.5820), City('Cologne', 'DE', 50.9375, 6.9603),
  City('Frankfurt', 'DE', 50.1109, 8.6821), City('Stuttgart', 'DE', 48.7758, 9.1829),
  City('Düsseldorf', 'DE', 51.2277, 6.7735), City('Leipzig', 'DE', 51.3397, 12.3731),
  City('Dresden', 'DE', 51.0504, 13.7373), City('Hanover', 'DE', 52.3759, 9.7320),
  City('Nuremberg', 'DE', 49.4521, 11.0767),
  // France
  City('Paris', 'FR', 48.8566, 2.3522), City('Marseille', 'FR', 43.2965, 5.3698),
  City('Lyon', 'FR', 45.7640, 4.8357), City('Toulouse', 'FR', 43.6047, 1.4442),
  City('Nice', 'FR', 43.7102, 7.2620), City('Nantes', 'FR', 47.2184, -1.5536),
  City('Bordeaux', 'FR', 44.8378, -0.5792), City('Lille', 'FR', 50.6292, 3.0573),
  City('Strasbourg', 'FR', 48.5734, 7.7521), City('Montpellier', 'FR', 43.6108, 3.8767),
  // Spain
  City('Madrid', 'ES', 40.4168, -3.7038), City('Barcelona', 'ES', 41.3874, 2.1686),
  City('Valencia', 'ES', 39.4699, -0.3763), City('Seville', 'ES', 37.3891, -5.9845),
  City('Bilbao', 'ES', 43.2630, -2.9350), City('Málaga', 'ES', 36.7213, -4.4214),
  // Italy
  City('Rome', 'IT', 41.9028, 12.4964), City('Milan', 'IT', 45.4642, 9.1900),
  City('Naples', 'IT', 40.8518, 14.2681), City('Turin', 'IT', 45.0703, 7.6869),
  City('Florence', 'IT', 43.7696, 11.2558), City('Bologna', 'IT', 44.4949, 11.3426),
  City('Venice', 'IT', 45.4408, 12.3155), City('Palermo', 'IT', 38.1157, 13.3615),
  // Netherlands
  City('Amsterdam', 'NL', 52.3676, 4.9041), City('Rotterdam', 'NL', 51.9244, 4.4777),
  City('The Hague', 'NL', 52.0705, 4.3007), City('Utrecht', 'NL', 52.0907, 5.1214),
  City('Eindhoven', 'NL', 51.4416, 5.4697), City('Groningen', 'NL', 53.2194, 6.5665),
  // Sweden
  City('Stockholm', 'SE', 59.3293, 18.0686), City('Gothenburg', 'SE', 57.7089, 11.9746),
  City('Malmö', 'SE', 55.6050, 13.0038), City('Uppsala', 'SE', 59.8586, 17.6389),
  // India
  City('Mumbai', 'IN', 19.0760, 72.8777), City('Delhi', 'IN', 28.7041, 77.1025),
  City('Bengaluru', 'IN', 12.9716, 77.5946), City('Hyderabad', 'IN', 17.3850, 78.4867),
  City('Chennai', 'IN', 13.0827, 80.2707), City('Kolkata', 'IN', 22.5726, 88.3639),
  City('Pune', 'IN', 18.5204, 73.8567), City('Ahmedabad', 'IN', 23.0225, 72.5714),
  City('Jaipur', 'IN', 26.9124, 75.7873), City('Chandigarh', 'IN', 30.7333, 76.7794),
  City('Kochi', 'IN', 9.9312, 76.2673), City('Goa', 'IN', 15.4909, 73.8278),
  City('Lucknow', 'IN', 26.8467, 80.9462), City('Shillong', 'IN', 25.5788, 91.8933),
  // Japan
  City('Tokyo', 'JP', 35.6762, 139.6503), City('Osaka', 'JP', 34.6937, 135.5023),
  City('Kyoto', 'JP', 35.0116, 135.7681), City('Yokohama', 'JP', 35.4437, 139.6380),
  City('Nagoya', 'JP', 35.1815, 136.9066), City('Sapporo', 'JP', 43.0618, 141.3545),
  City('Fukuoka', 'JP', 33.5904, 130.4017), City('Sendai', 'JP', 38.2682, 140.8694),
  // South Korea
  City('Seoul', 'KR', 37.5665, 126.9780), City('Busan', 'KR', 35.1796, 129.0756),
  City('Incheon', 'KR', 37.4563, 126.7052), City('Daegu', 'KR', 35.8714, 128.6014),
  // Philippines
  City('Manila', 'PH', 14.5995, 120.9842), City('Cebu City', 'PH', 10.3157, 123.8854),
  City('Davao City', 'PH', 7.1907, 125.4553),
  // Brazil
  City('São Paulo', 'BR', -23.5505, -46.6333), City('Rio de Janeiro', 'BR', -22.9068, -43.1729),
  City('Brasília', 'BR', -15.8267, -47.9218), City('Belo Horizonte', 'BR', -19.9167, -43.9345),
  City('Porto Alegre', 'BR', -30.0346, -51.2177), City('Curitiba', 'BR', -25.4284, -49.2733),
  City('Salvador', 'BR', -12.9777, -38.5016), City('Recife', 'BR', -8.0476, -34.8770),
  City('Fortaleza', 'BR', -3.7319, -38.5267),
  // Mexico
  City('Mexico City', 'MX', 19.4326, -99.1332), City('Guadalajara', 'MX', 20.6597, -103.3496),
  City('Monterrey', 'MX', 25.6866, -100.3161), City('Puebla', 'MX', 19.0414, -98.2063),
  City('Tijuana', 'MX', 32.5149, -117.0382), City('Mérida', 'MX', 20.9674, -89.5926),
  City('Querétaro', 'MX', 20.5888, -100.3899),
  // South Africa
  City('Johannesburg', 'ZA', -26.2041, 28.0473), City('Cape Town', 'ZA', -33.9249, 18.4241),
  City('Durban', 'ZA', -29.8587, 31.0218), City('Pretoria', 'ZA', -25.7479, 28.2293),
  // Nigeria
  City('Lagos', 'NG', 6.5244, 3.3792), City('Abuja', 'NG', 9.0765, 7.3986),
  City('Ibadan', 'NG', 7.3775, 3.9470), City('Port Harcourt', 'NG', 4.8156, 7.0498),
];

List<City> citiesFor(String marketCode) => kCities.where((c) => c.country == marketCode).toList();
