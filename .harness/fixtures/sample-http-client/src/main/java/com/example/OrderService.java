package com.example;

import java.util.HashMap;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

@Service
public class OrderService {

    private final RestTemplate restTemplate = new RestTemplate();

    public Map<String, Object> createOrder(String itemId, int quantity) {
        String inventoryUrl = "http://inventory-service:8080/api/stock/" + itemId;
        Map stockResponse = restTemplate.getForObject(inventoryUrl, Map.class);

        String userUrl = "http://user-service:8080/api/users/current";
        Map userResponse = restTemplate.exchange(userUrl,
            org.springframework.http.HttpMethod.GET, null, Map.class).getBody();

        Map<String, Object> result = new HashMap<>();
        result.put("stock", stockResponse);
        result.put("user", userResponse);
        return result;
    }

    public void notifyLogistics(String orderId) {
        restTemplate.postForObject(
            "http://logistics-service:8080/api/deliveries",
            Map.of("orderId", orderId),
            Map.class
        );
    }
}
