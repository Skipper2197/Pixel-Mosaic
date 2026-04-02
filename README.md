# Pixel-Mosaic

### LAB vs RGB
The distance between two raw RGB values does not align with how we perceive color. A smaller change in Green is way more noticable than a small change in Blue. LAB fixes this. [Read This](https://www.pantone.com/articles/color-fundamentals/understanding-different-color-spaces?srsltid=AfmBOopapipNjzlp334hWubE6OLnPsM_hpJGwBax3C6W5VLJ1Syv1Cxv)  

LAB stands for:
- Lightness
- A = axis between Green (-) and Red (+)
- B = axis between Blue (-) and Yellow (+)  

When calculating the distance between two LAB points using Euclidean distance, the result directly correlates with how different those colors are to humans. This allows for chunks to be replaced by mathematically similar pictures with respect to color.       

### k-d Tree
A brute force search would require multiple billion comparisons. Even on an HPC, this would take a while. A k-d tree (k-dimensional tree) solves this problem.  

A k-d tree is a binary search tree for many points. It organizes points into a map by splitting the overall image space based on similarity parameters. In this case, it splits based on the LAB value. There will be three "splits":
- One for Lightness, splitting into light vs dark
- After splitting for Lightness, split by A, Red vs Green
- Finally split by B, Blue vs Yellow    

Instead of searching each point, this tree checks for buckets of images based on the LAB values, greatly speeding up this process.

### LAB Value Storage
Use a numpy array to store the raw LAB values in a 2D array. This allows for fast reading and writing of new data. Index this array based on image names. If the best match is row 100,000 then the corresponding picture will be images_names[100,000]

### Generate Thumbnails of Full Size Pictures
~~~bash
magick mogrify -path thumbnails/ -thumbnail 32x32^ -gravity center -extent 32x32 *.jpg
~~~