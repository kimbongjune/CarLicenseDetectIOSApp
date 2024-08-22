//
//  ApiService.swift
//  CarLicense
//
//  Created by 김봉준 on 8/22/24.
//

import Foundation
import UIKit

struct ApiResponse: Codable {
    let prediction: String?
    let texts: [String]?
    let licensePlateImage: String?
    
    // 키와 이름을 맞추기 위해 CodingKeys를 정의
    enum CodingKeys: String, CodingKey {
        case prediction
        case texts
        case licensePlateImage = "license_plate_image"
    }
}

class ApiService {
    static let shared = ApiService()
    private let baseURL = URL(string: "http://192.168.0.46:5500")! // 서버 주소

    func uploadImage(image: UIImage, completion: @escaping (Result<ApiResponse, Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "Invalid image data", code: 0, userInfo: nil)))
            return
        }

        let url = baseURL.appendingPathComponent("/api/upload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Multipart body 생성
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = NSMutableData()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body as Data

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: 0, userInfo: nil)))
                return
            }

            do {
                let apiResponse = try JSONDecoder().decode(ApiResponse.self, from: data)
                completion(.success(apiResponse))
            } catch let jsonError {
                completion(.failure(jsonError))
            }
        }

        task.resume()
    }
}

// Helper extension to append strings to NSMutableData
extension NSMutableData {
    func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
